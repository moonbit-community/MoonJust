///|
fn fake_context() -> (@host.FakeHost, @application.ApplicationContext) raise {
  let cwd = @path.PathValue::new("/workspace", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  (host, @application.ApplicationContext::new(cwd))
}

///|
test "format check never mutates and reports changed source" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"x:=\"y\"\n")
  let arguments = @cli.parse_arguments(["--fmt", "--check"], {})
  let response = @application.execute_file_command(host, arguments, context)
  assert_eq(response.exit_code(), 1)
  assert_true((try! @utf8.decode(response.stdout())).contains("+x := \"y\""))
  assert_eq(host.read_file(file), b"x:=\"y\"\n")
}

///|
test "format writes only after a successful parse" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"x:=\"y\"\n")
  let arguments = @cli.parse_arguments(["--fmt"], {})
  let response = @application.execute_file_command(host, arguments, context)
  assert_eq(response.exit_code(), 0)
  assert_eq(host.read_file(file), b"x := \"y\"\n")
  host.put_file(file, b"x := \"unterminated\n")
  try @application.execute_file_command(host, arguments, context) catch {
    Load(_) | Format(_) => ()
    error => fail("unexpected application error: \{Repr(error)}")
  } noraise {
    _ => fail("expected malformed source failure")
  }
  assert_eq(host.read_file(file), b"x := \"unterminated\n")
}

///|
test "stdin format returns stdout and does not require a file" {
  let (host, context) = fake_context()
  let context = @application.ApplicationContext::new(
    context.cwd(),
    stdin=b"x:=\"y\"\n",
  )
  let arguments = @cli.parse_arguments(["--fmt", "--justfile", "-"], {})
  let response = @application.execute_file_command(host, arguments, context)
  assert_eq(response.exit_code(), 0)
  assert_eq(response.stdout(), b"x := \"y\"\n")
}

///|
test "init creates the canonical template and refuses overwrite" {
  let (host, context) = fake_context()
  let arguments = @cli.parse_arguments(["--init"], {})
  let response = @application.execute_file_command(host, arguments, context)
  assert_eq(response.exit_code(), 0)
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  assert_true((try! @utf8.decode(host.read_file(file))).contains("default:"))
  try @application.execute_file_command(host, arguments, context) catch {
    AlreadyExists(path) => assert_eq(path, file)
    error => fail("unexpected application error: \{Repr(error)}")
  } noraise {
    _ => fail("expected overwrite refusal")
  }
}

///|
test "format surfaces write denial and accepts upstream dry-run semantics" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"x:=\"y\"\n")
  let arguments = @cli.parse_arguments(["--fmt", "--dry-run"], {})
  host.deny(FsWrite)
  try @application.execute_file_command(host, arguments, context) catch {
    Host(CapabilityDenied(FsWrite)) => ()
    error => fail("unexpected permission error: \{Repr(error)}")
  } noraise {
    _ => fail("expected write denial")
  }
  assert_eq(host.read_file(file), b"x:=\"y\"\n")
  host.allow(FsWrite)
  ignore(@application.execute_file_command(host, arguments, context))
  assert_eq(host.read_file(file), b"x := \"y\"\n")
}

///|
test "list renders docs aliases groups and hides private recipes" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(
    file, b"# greeting\nhello:\n\n[group(\"ci\")]\n[doc(\"build docs\")]\nbuild target:\n\n[private]\nsecret:\n\nalias b := build\n",
  )
  let arguments = @cli.parse_arguments(["--list", "--unsorted"], {})
  let response = @application.execute_query_command(host, arguments, context)
  let text = try! @utf8.decode(response.stdout())
  assert_true(text.contains("hello"))
  assert_true(text.contains("# greeting"))
  assert_true(text.contains("[ci]\n"))
  assert_true(text.contains("build target # build docs [alias: b]"))
  assert_false(text.contains("secret"))
}

///|
test "summary supports sorted and source-order output" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"zeta:\n\nalpha:\n")
  let sorted = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--summary"], {}),
    context,
  )
  assert_eq(sorted.stdout(), b"alpha zeta\n")
  let source_order = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--summary", "--unsorted"], {}),
    context,
  )
  assert_eq(source_order.stdout(), b"zeta alpha\n")
}

///|
test "show and usage resolve aliases without executing recipes" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(
    file, b"build target +rest:\n  echo {{target}}\n\nalias b := build\n",
  )
  let shown = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--show", "b"], {}),
    context,
  )
  assert_true(
    (try! @utf8.decode(shown.stdout())).contains("build target +rest:"),
  )
  let usage = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--usage", "b"], {}),
    context,
  )
  assert_eq(
    usage.stdout(),
    b"Usage: just build target rest...\n\nArguments:\n  target\n  rest...\n",
  )
  assert_eq(host.process_calls().length(), 0)
}

///|
test "groups are deduplicated and Unicode list padding uses display width" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(
    file,
    @utf8.encode("[group(\"ci\")]\nalpha:\n\n[group(\"ci\")]\nwide_name:\n"),
  )
  let groups = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--groups"], {}),
    context,
  )
  assert_eq(groups.stdout(), b"Recipe groups:\n    ci\n")
}

///|
test "variables and evaluate match stable upstream ordering and newlines" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"z := \"z\"\na := \"a\"\njoined := a + z\n")
  let variables = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--variables"], {}),
    context,
  )
  assert_eq(variables.stdout(), b"a joined z\n")
  let all = @application.execute_inspect_command(
    host,
    @cli.parse_arguments(["--evaluate"], {}),
    context,
  )
  assert_eq(
    all.stdout(),
    b"a      := \"a\"\njoined := \"az\"\nz      := \"z\"\n",
  )
  let one = @application.execute_inspect_command(
    host,
    @cli.parse_arguments(["--evaluate", "joined"], {}),
    context,
  )
  assert_eq(one.stdout(), b"az")
}

///|
test "evaluate shell escapes output and excludes private variables" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(
    file, b"export public-name := \"$HOME\"\n_hidden := `echo secret`\n",
  )
  let response = @application.execute_inspect_command(
    host,
    @cli.parse_arguments(["--evaluate", "--evaluate-format", "shell"], {}),
    context,
  )
  assert_eq(response.stdout(), b"export public_name=\"\\$HOME\"\n")
  assert_eq(host.process_calls().length(), 0)
}

///|
test "requested effectful evaluation fails without process capability" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"danger := `echo secret`\n")
  let arguments = try! @cli.parse_arguments(["--evaluate", "danger"], {})
  try @application.execute_inspect_command(host, arguments, context) catch {
    Evaluation(error) =>
      assert_true(error is EffectRequired(effect="process", ..))
    error => fail("unexpected evaluation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected process effect rejection")
  }
  assert_eq(host.process_calls().length(), 0)
}

///|
test "dump and JSON inspect are deterministic and schema-pinned" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(
    file, b"x := \"a\"\njoined := x + \"b\"\nbuild target=\"dev\":\n  echo {{target}}\n",
  )
  let dump = @application.execute_inspect_command(
    host,
    @cli.parse_arguments(["--dump"], {}),
    context,
  )
  assert_true(
    (try! @utf8.decode(dump.stdout())).contains("joined := x + \"b\""),
  )
  let arguments = @cli.parse_arguments(["--json"], {})
  let first = @application.execute_inspect_command(host, arguments, context)
  let second = @application.execute_inspect_command(host, arguments, context)
  assert_eq(first.stdout(), second.stdout())
  let parsed = try! @json.parse(try! @utf8.decode(first.stdout()))
  guard parsed is Object(root) else { fail("expected JSON object") }
  assert_true(root.contains("assignments"))
  assert_true(root.contains("recipes"))
  assert_true(root.contains("settings"))
  assert_eq(@application.inspect_json_schema_version(), 1)
  let dump_json = @application.execute_inspect_command(
    host,
    @cli.parse_arguments(["--dump", "--dump-format", "json"], {}),
    context,
  )
  assert_eq(dump_json.stdout(), first.stdout())
  assert_eq(host.process_calls().length(), 0)
}
