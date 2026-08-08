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
  assert_eq(
    response.stderr(),
    b"error: formatted justfile differs from original\n",
  )
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
  assert_true(
    (try! @utf8.decode(response.stderr())).contains("wrote justfile to `"),
  )
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
test "format writes a canonical symlink target and leaves the display path intact" {
  let (host, context) = fake_context()
  let link = @path.PathValue::new("/workspace/justfile", Unix)
  let target = @path.PathValue::new("/workspace/actual.just", Unix)
  host.put_file(link, b"x:=\"y\"\n")
  host.put_file(target, b"x:=\"y\"\n")
  host.set_canonical(link, target)
  let response = @application.execute_file_command(
    host,
    @cli.parse_arguments(["--fmt"], {}),
    context,
  )
  assert_eq(response.stderr(), b"wrote justfile to `/workspace/justfile`\n")
  assert_eq(host.read_file(target), b"x := \"y\"\n")
  assert_eq(host.read_file(link), b"x:=\"y\"\n")
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
test "relative justfile and working directory use explicit invocation cwd" {
  let cwd = @path.PathValue::new("/workspace/invocation", Unix)
  let host = @host.FakeHost::new(
    @path.PathValue::new("/ambient/ignored", Unix),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let file = @path.PathValue::new("/workspace/config/justfile", Unix)
  host.put_file(file, b"build:\n")
  let arguments = try! @cli.parse_arguments(
    [
      "--justfile", "../config/justfile", "--working-directory", "../run", "build",
    ],
    {},
  )
  try
    @application.execute_command(
      host,
      arguments,
      @application.ApplicationContext::new(cwd),
    )
  catch {
    UnsupportedCommand("recipe execution") => ()
    error => fail("unexpected relative input error: \{Repr(error)}")
  } noraise {
    _ => fail("expected Phase 8 executor boundary")
  }
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
test "init honors explicit files and directories without silent fallback" {
  let (host, context) = fake_context()
  let explicit = @application.execute_file_command(
    host,
    @cli.parse_arguments(["--init", "--justfile", "custom.just"], {}),
    context,
  )
  assert_eq(explicit.stderr(), b"wrote justfile to `/workspace/custom.just`\n")
  assert_true(
    (try! @utf8.decode(
      host.read_file(@path.PathValue::new("/workspace/custom.just", Unix)),
    )).contains("default:"),
  )
  let nested = @application.execute_file_command(
    host,
    @cli.parse_arguments(["--init", "nested"], {}),
    context,
  )
  assert_eq(
    nested.stderr(),
    b"wrote justfile to `/workspace/nested/justfile`\n",
  )
  assert_true(
    (try! @utf8.decode(
      host.read_file(@path.PathValue::new("/workspace/nested/justfile", Unix)),
    )).contains("default:"),
  )
  try
    @application.execute_file_command(
      host,
      @cli.parse_arguments(["--init", "one", "two"], {}),
      context,
    )
  catch {
    @application.Query(message) =>
      assert_true(message.contains("unexpected argument"))
    error => fail("unexpected init argument error: \{Repr(error)}")
  } noraise {
    _ => fail("expected init to reject extra arguments")
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
  host.put_file(file, b"")
  let empty = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--summary"], {}),
    context,
  )
  assert_eq(empty.stdout(), b"\n")
  assert_eq(empty.stderr(), b"justfile contains no recipes\n")
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
    b"alias b := build\nUsage: just b target rest...\n\nArguments:\n  target\n  rest...\n",
  )
  assert_eq(host.process_calls().length(), 0)
  try
    @application.execute_query_command(
      host,
      @cli.parse_arguments(["--show", "b", "extra"], {}),
      context,
    )
  catch {
    @application.Query(message) =>
      assert_true(message.contains("unexpected argument"))
    error => fail("unexpected show argument error: \{Repr(error)}")
  } noraise {
    _ => fail("expected show to reject extra arguments")
  }
  try
    @application.execute_query_command(
      host,
      @cli.parse_arguments(["--show", "buil"], {}),
      context,
    )
  catch {
    @application.Query(message) =>
      assert_true(message.contains("Did you mean `build`?"))
    error => fail("unexpected show suggestion error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unknown recipe failure")
  }
}

///|
test "list and usage collapse option parameters and render option metadata" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(
    file, b"set lists\n[arg('flag', long, flag, help='toggle')]\n[arg('item', short, pattern=['one', 'two'])]\nrun flag item positional='x':\n",
  )
  let listed = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--list"], {}),
    context,
  )
  assert_eq(
    listed.stdout(),
    b"Available recipes:\n    run [OPTIONS] positional='x'\n",
  )
  let usage = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--usage", "run"], {}),
    context,
  )
  assert_eq(
    usage.stdout(),
    b"Usage: just run [OPTIONS] [positional]\n\nArguments:\n  [positional] [default: 'x']\n\nOptions:\n      --flag toggle\n  -i item [pattern: 'one' | 'two']\n",
  )
}

///|
test "run commands validate invocation before the Phase 8 executor boundary" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(
    file, b"[arg('target', long='target', pattern='debug|release')]\nbuild target:\n",
  )
  try
    @application.execute_command(
      host,
      @cli.parse_arguments(["build"], {}),
      context,
    )
  catch {
    @application.Invocation(error) =>
      assert_eq(error.message(), "recipe `build` requires option `--target`")
    error => fail("unexpected missing option error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invocation validation failure")
  }
  try
    @application.execute_command(
      host,
      @cli.parse_arguments(["build", "--target", "invalid"], {}),
      context,
    )
  catch {
    @application.Invocation(error) =>
      assert_true(error.message().contains("does not match pattern"))
    error => fail("unexpected pattern error: \{Repr(error)}")
  } noraise {
    _ => fail("expected pattern validation failure")
  }
  try
    @application.execute_command(
      host,
      @cli.parse_arguments(["build", "--target", "release"], {}),
      context,
    )
  catch {
    @application.UnsupportedCommand("recipe execution") => ()
    error => fail("unexpected executor boundary error: \{Repr(error)}")
  } noraise {
    _ => fail("expected Phase 8 executor boundary")
  }
  assert_eq(host.process_calls().length(), 0)
}

///|
test "CLI variable overrides reach evaluate and invocation validation" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(
    file, b"mode := 'debug'\nderived := mode + '-mode'\n[arg('target', long, value=mode, pattern=['release'])]\nbuild target:\n",
  )
  let evaluated = try! @application.execute_command(
    host,
    @cli.parse_arguments(
      ["--evaluate", "derived", "--set", "mode", "release"],
      {},
    ),
    context,
  )
  assert_eq(evaluated.stdout(), b"release-mode")
  let listed = try! @application.execute_command(
    host,
    @cli.parse_arguments(["--list", "--set", "mode", "release"], {}),
    context,
  )
  assert_true((try! @utf8.decode(listed.stdout())).contains("build"))
  try
    @application.execute_command(
      host,
      @cli.parse_arguments(["--set", "mode", "release", "build", "--target"], {}),
      context,
    )
  catch {
    @application.UnsupportedCommand("recipe execution") => ()
    error => fail("unexpected override invocation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected Phase 8 executor boundary")
  }
  try
    @application.execute_command(
      host,
      @cli.parse_arguments(
        ["--set", "missing", "secret-value", "build", "--target"],
        {},
      ),
      context,
    )
  catch {
    @application.Evaluation(UnknownOverrides(names~, ..)) =>
      assert_eq(names, ["missing"])
    error => fail("unexpected unknown override error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unknown override failure")
  }
  try
    @application.execute_command(
      host,
      @cli.parse_arguments(
        ["--set", "bad::", "secret-value", "build", "--target"],
        {},
      ),
      context,
    )
  catch {
    @application.Environment(InvalidOverridePath(path~)) =>
      assert_eq(path, "bad::")
    error => fail("unexpected invalid override path error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid override path failure")
  }
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
  let custom = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--groups", "--list-prefix", " -> "], {}),
    context,
  )
  assert_eq(custom.stdout(), b"Recipe groups:\n -> ci\n")
  try
    @application.execute_query_command(
      host,
      @cli.parse_arguments(["--groups", "ci"], {}),
      context,
    )
  catch {
    @application.Query(message) =>
      assert_true(message.contains("unexpected argument"))
    error => fail("unexpected groups argument error: \{Repr(error)}")
  } noraise {
    _ => fail("expected groups to reject extra arguments")
  }
  try
    @application.execute_query_command(
      host,
      @cli.parse_arguments(["--list", "--group", "missing"], {}),
      context,
    )
  catch {
    @application.Query(message) =>
      assert_true(message.contains("does not contain group"))
    error => fail("unexpected unknown group error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unknown group failure")
  }
}

///|
test "list repeats recipes in each distinct group and filters multiple groups" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(
    file, b"[group('alpha')]\na:\n[group('alpha')]\n[group('beta')]\nb:\nc:\n[group('beta')]\nd:\n",
  )
  let all = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--list"], {}),
    context,
  )
  assert_eq(
    all.stdout(),
    b"Available recipes:\n    c\n\n    [alpha]\n    a\n    b\n\n    [beta]\n    b\n    d\n",
  )
  let selected = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--list", "--group", "alpha", "--group", "beta"], {}),
    context,
  )
  assert_eq(
    selected.stdout(),
    b"Available recipes:\n    [alpha]\n    a\n    b\n\n    [beta]\n    b\n    d\n",
  )
}

///|
test "list groups recipes once and supports every upstream alias style" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(
    file, b"[group(\"z\")]\nb:\n\n# doc\nx target=\"dev\":\n\n[group(\"z\")]\na:\n\nalias short := x\nalias y := x\n",
  )
  let separate = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--list", "--alias-style", "separate"], {}),
    context,
  )
  assert_eq(
    separate.stdout(),
    b"Available recipes:\n    x target=\"dev\"     # doc\n    short target=\"dev\" # alias for `x`\n    y target=\"dev\"     # alias for `x`\n\n    [z]\n    a\n    b\n",
  )
  let left = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--list", "--alias-style", "left"], {}),
    context,
  )
  assert_true(
    (try! @utf8.decode(left.stdout())).contains(
      "x target=\"dev\" # [aliases: short, y] doc",
    ),
  )
  let unsorted = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--list", "--unsorted"], {}),
    context,
  )
  assert_true(
    (try! @utf8.decode(unsorted.stdout())).contains("[z]\n    b\n    a"),
  )
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
