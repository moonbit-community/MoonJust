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
test "application semantic diagnostics retain source positions" {
  let (host, context) = fake_context()
  host.put_file(
    @path.PathValue::new("/workspace/justfile", Unix),
    b"set tempdir := missing\ndefault:\n",
  )
  let arguments = try! @cli.parse_arguments([], {})
  try @application.execute_query_command(host, arguments, context) catch {
    error => {
      let rendered = @application.render_application_error(
        host, arguments, context, error,
      )
      assert_true(rendered.contains("error: variable `missing` not defined"))
      assert_true(rendered.contains("justfile:1:16"))
      assert_true(rendered.contains("set tempdir := missing"))
    }
  } noraise {
    _ => fail("expected undefined setting variable")
  }
}

///|
async test "dotenv entries are inherited by planning backticks" {
  let (host, context) = fake_context()
  host.put_file(
    @path.PathValue::new("/workspace/justfile", Unix),
    b"set dotenv-load\nX := `echo $DOTENV_KEY`\necho:\n  echo {{X}}\n",
  )
  host.put_file(
    @path.PathValue::new("/workspace/.env", Unix),
    b"DOTENV_KEY=dotenv-value\n",
  )
  let expected = try! @host.CommandSpec::new("sh", ["-cu", "echo $DOTENV_KEY"])
  expected.set_cwd(@path.PathValue::new("/workspace", Unix))
  expected.set_inherit_environment(false)
  try! expected.add_environment("DOTENV_KEY", "dotenv-value")
  expected.set_inherit_stdin(true)
  expected.set_stdout(Capture)
  expected.set_stderr(Inherit)
  host.expect_process(
    expected,
    @host.ProcessResult::new(0, b"dotenv-value\n", b""),
  )
  try
    @application.plan_run_command_async(
      host,
      host,
      host,
      try! @cli.parse_arguments(["echo"], {}),
      context,
    )
  catch {
    error => fail("unexpected dotenv planning error: \{Repr(error)}")
  } noraise {
    _ => ()
  }
  assert_eq(host.pending_process_expectations(), 0)
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
async test "async file commands preserve init and format transactions" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  let initialized = @application.execute_file_command_async(
    host,
    @cli.parse_arguments(["--init"], {}),
    context,
  )
  assert_eq(initialized.exit_code(), 0)
  assert_eq(
    host.read_file(file),
    b"# https://just.systems\n\ndefault:\n    echo 'Hello, world!'\n",
  )
  host.put_file(file, b"x:=\"y\"\n")
  let formatted = @application.execute_file_command_async(
    host,
    @cli.parse_arguments(["--fmt"], {}),
    context,
  )
  assert_eq(formatted.exit_code(), 0)
  assert_eq(host.read_file(file), b"x := \"y\"\n")
}

///|
test "Markdown format prints canonical source without mutation" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/tasks.MD", Unix)
  let original = b"# prose\n```just\nx:=\"y\"\n```\n"
  host.put_file(file, original)
  let response = @application.execute_file_command(
    host,
    @cli.parse_arguments(["--fmt", "--justfile", "tasks.MD"], {}),
    context,
  )
  assert_eq(response.exit_code(), 0)
  assert_true((try! @utf8.decode(response.stdout())).contains("x := \"y\""))
  assert_eq(response.stderr(), b"")
  assert_eq(try! host.read_file(file), original)
}

///|
test "justfile-name discovers and tangles Markdown" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/tasks.md", Unix)
  host.put_file(file, b"```just\nbuild:\n```\n")
  let response = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--list", "--justfile-name", "tasks.md"], {}),
    context,
  )
  assert_true((try! @utf8.decode(response.stdout())).contains("build"))
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
    _ => fail("expected executor boundary")
  }
}

///|
async test "string settings select dotenv and temporary directories" {
  let (host, context) = fake_context()
  host.put_file(
    @path.PathValue::new("/workspace/justfile", Unix),
    b"set dotenv-filename := \".env.ci\"\nset tempdir := \".tmp\"\n[script]\nbuild:\n  echo ok\n",
  )
  host.put_file(@path.PathValue::new("/workspace/.env.ci", Unix), b"MODE=ci\n")
  let plan = try! @application.plan_run_command_async(
    host,
    host,
    host,
    try! @cli.parse_arguments(["build"], {}),
    context,
  )
  match plan.tasks()[0].steps()[0] {
    Script(script, _) => {
      assert_eq(
        script.configuration().temporary_directory(),
        @path.PathValue::new("/workspace/.tmp", Unix),
      )
      assert_true(script.environment().contains(("MODE", "ci")))
    }
    _ => fail("expected string-setting script task")
  }
}

///|
async test "platform attributes select non-recipe definitions in project planning" {
  let cwd = @path.PathValue::new("/workspace", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Macos, "aarch64", Unix),
  )
  let context = @application.ApplicationContext::new(cwd)
  host.put_file(
    @path.PathValue::new("/workspace/justfile", Unix),
    b"[unix]\nx := 'unix'\n\n[windows]\nx := 'windows'\n\nfoo:\n  @echo {{ x }}\n",
  )
  let plan = try! @application.plan_run_command_async(
    host,
    host,
    host,
    try! @cli.parse_arguments(["foo"], {}),
    context,
  )
  assert_eq(plan.tasks().length(), 1)
}

///|
async test "async dotenv commands populate recipe environments" {
  let (host, context) = fake_context()
  host.put_file(
    @path.PathValue::new("/workspace/justfile", Unix),
    b"set dotenv-command := 'emit'\n[script]\nbuild:\n  echo ok\n",
  )
  let expected = try! @host.CommandSpec::new("sh", ["-cu", "emit"])
  expected.set_cwd(@path.PathValue::new("/workspace", Unix))
  expected.set_inherit_stdin(true)
  expected.set_stdout(Capture)
  expected.set_stderr(Inherit)
  host.expect_process(
    expected,
    @host.ProcessResult::new(0, b"MODE=async\n", b""),
  )
  let plan = try! @application.plan_run_command_async(
    host,
    host,
    host,
    try! @cli.parse_arguments(["build"], {}),
    context,
  )
  match plan.tasks()[0].steps()[0] {
    Script(script, _) =>
      assert_true(script.environment().contains(("MODE", "async")))
    _ => fail("expected dotenv command script task")
  }
  assert_eq(host.pending_process_expectations(), 0)
}

///|
async test "module working-directory selects recipe cwd" {
  let (host, context) = fake_context()
  host.put_file(
    @path.PathValue::new("/workspace/justfile", Unix),
    b"set working-directory := \"build\"\n[script]\nrun:\n  echo ok\n",
  )
  let plan = try! @application.plan_run_command_async(
    host,
    host,
    host,
    try! @cli.parse_arguments(["run"], {}),
    context,
  )
  match plan.tasks()[0].steps()[0] {
    Script(script, _) =>
      assert_eq(script.cwd(), @path.PathValue::new("/workspace/build", Unix))
    _ => fail("expected working-directory line task")
  }
}

///|
async test "recipe no-cd selects the original invocation directory" {
  let cwd = @path.PathValue::new("/workspace/child", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  host.put_file(
    @path.PathValue::new("/workspace/justfile", Unix),
    b"[no-cd]\n[script]\ndefault:\n  echo ok\n",
  )
  let plan = try! @application.plan_run_command_async(
    host,
    host,
    host,
    try! @cli.parse_arguments([], {}),
    @application.ApplicationContext::new(cwd),
  )
  match plan.tasks()[0].steps()[0] {
    Script(script, _) => assert_eq(script.cwd(), cwd)
    _ => fail("expected no-cd script task")
  }
}

///|
async test "recipe working-directory overrides module no-cd" {
  let (host, context) = fake_context()
  host.put_file(
    @path.PathValue::new("/workspace/justfile", Unix),
    b"set no-cd\n[working-directory('build')]\n[script]\nrun:\n  echo ok\n",
  )
  let plan = try! @application.plan_run_command_async(
    host,
    host,
    host,
    try! @cli.parse_arguments(["run"], {}),
    context,
  )
  match plan.tasks()[0].steps()[0] {
    Script(script, _) =>
      assert_eq(script.cwd(), @path.PathValue::new("/workspace/build", Unix))
    _ => fail("expected working-directory script task")
  }
}

///|
test "global context follows Linux XDG lookup and project root" {
  let cwd = @path.PathValue::new("/workspace/repo/sub", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  host.set_env("HOME", "/home/test")
  host.set_env("XDG_CONFIG_HOME", "/config")
  host.put_file(
    @path.PathValue::new("/config/just/JUSTFILE", Unix),
    b"@default:\n  pwd\n",
  )
  host.put_file(
    @path.PathValue::new("/home/test/.config/just/justfile", Unix),
    b"wrong:\n",
  )
  host.put_file(@path.PathValue::new("/workspace/repo/.git", Unix), b"")
  let context = @application.resolve_global_context(
    host,
    host,
    @cli.parse_arguments(["--global-justfile"], {}),
    @application.ApplicationContext::new(cwd),
  )
  assert_eq(
    context.global_justfile(),
    Some(@path.PathValue::new("/config/just/JUSTFILE", Unix)),
  )
  assert_eq(
    context.global_project_directory(),
    Some(@path.PathValue::new("/workspace/repo", Unix)),
  )
}

///|
async test "global recipes use the invocation project instead of config cwd" {
  let cwd = @path.PathValue::new("/workspace/project", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Macos, "aarch64", Unix),
  )
  host.set_env("HOME", "/home/test")
  host.put_file(
    @path.PathValue::new(
      "/home/test/Library/Application Support/just/JustFile",
      Unix,
    ),
    b"[script]\n@default:\n  pwd\n",
  )
  host.put_file(
    @path.PathValue::new("/home/test/.config/just/justfile", Unix),
    b"wrong:\n",
  )
  let arguments = @cli.parse_arguments(["--global-justfile"], {})
  let context = @application.resolve_global_context(
    host,
    host,
    arguments,
    @application.ApplicationContext::new(cwd),
  )
  let plan = @application.plan_run_command_async(
    host, host, host, arguments, context,
  )
  match plan.tasks()[0].steps()[0] {
    Script(script, _) => assert_eq(script.cwd(), cwd)
    _ => fail("expected global script task")
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
test "format and dump honor indentation overrides and settings" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"foo:\n    echo hi\n")
  ignore(
    @application.execute_file_command(
      host,
      @cli.parse_arguments(["--fmt", "--indentation", "  "], {}),
      context,
    ),
  )
  assert_eq(host.read_file(file), b"foo:\n  echo hi\n")
  host.put_file(file, b"set indentation := '\t'\n\nfoo:\n    echo hi\n")
  let dumped = @application.execute_inspect_command(
    host,
    @cli.parse_arguments(["--dump"], {}),
    context,
  )
  assert_eq(dumped.stdout(), b"set indentation := '\t'\n\nfoo:\n\techo hi\n")
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
test "list evaluates doc expressions, joins lists, and renders multiline docs" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(
    file, b"set lists\nprefix := 'hello '\n[doc(prefix + 'world')]\nexpression:\n\n[doc(['hello', 'world'])]\nlisted:\n\n[doc('multiline\ncomment')]\nmultiline:\n\n# hidden\n[doc]\nsuppressed:\n",
  )
  let response = @application.execute_query_command(
    host,
    try! @cli.parse_arguments(["--unstable", "--list", "--unsorted"], {}),
    context,
  )
  assert_eq(
    response.stdout(),
    b"Available recipes:\n    expression # hello world\n    listed     # hello world\n    # multiline\n    # comment\n    multiline\n    suppressed\n",
  )
}

///|
test "list color highlights doc backticks on stdout" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(
    file, b"# Comment `` `with backticks` and trailing text\nrecipe:\n",
  )
  let forced = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--list", "--color", "always"], {}),
    context,
  )
  assert_eq(
    forced.stdout(),
    @utf8.encode(
      "Available recipes:\n    recipe \u{001b}[34m#\u{001b}[0m " +
      "\u{001b}[34mComment \u{001b}[0m" +
      "\u{001b}[36m``\u{001b}[0m" +
      "\u{001b}[34m \u{001b}[0m" +
      "\u{001b}[36m`with backticks`\u{001b}[0m" +
      "\u{001b}[34m and trailing text\u{001b}[0m\n",
    ),
  )
  host.put_file(file, b"# Comment `with unclosed backtick\nrecipe:\n")
  let unclosed = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--list", "--color=always"], {}),
    context,
  )
  assert_true(
    (try! @utf8.decode(unclosed.stdout())).contains(
      "\u{001b}[36m`with unclosed backtick\u{001b}[0m",
    ),
  )
}

///|
test "list auto and never color obey stdout terminal" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"# `doc`\nrecipe:\n")
  host.set_terminal(@host.TerminalInfo::new(false, true, false, true))
  let automatic = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--list"], {}),
    context,
  )
  assert_true((try! @utf8.decode(automatic.stdout())).contains("\u{001b}[36m"))
  let never = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--list", "--color", "never"], {}),
    context,
  )
  assert_false((try! @utf8.decode(never.stdout())).contains("\u{001b}["))
  host.set_terminal(@host.TerminalInfo::new(false, false, true, true))
  let redirected = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--list"], {}),
    context,
  )
  assert_false((try! @utf8.decode(redirected.stdout())).contains("\u{001b}["))
}

///|
test "list places wide signature documentation above" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(
    file, b"# comment\nfoo bar=\"..................................................\":\n# short\ntiny:\n",
  )
  let listed = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--list"], {}),
    context,
  )
  assert_eq(
    listed.stdout(),
    b"Available recipes:\n    # comment\n    foo bar=\"..................................................\"\n    tiny # short\n",
  )
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
  host.put_file(file, b"build: missing\n")
  try
    @application.execute_query_command(
      host,
      @cli.parse_arguments(["--summary"], {}),
      context,
    )
  catch {
    @application.Semantic(UnknownDependency(target~, ..)) =>
      assert_eq(target, "missing")
    error => fail("unexpected summary error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unknown dependency error")
  }
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
  host.put_file(
    file, b"# hidden\n[doc('replacement')]\nbuild:\n\n# visible\n[private]\nother:\n",
  )
  let documented = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--show", "build"], {}),
    context,
  )
  assert_eq(documented.stdout(), b"[doc('replacement')]\nbuild:\n")
  let private = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--show", "other"], {}),
    context,
  )
  assert_eq(private.stdout(), b"# visible\n[private]\nother:\n")
  host.put_file(
    file, b"build target +rest:\n  echo {{target}}\n\nalias b := build\n",
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
    @cli.parse_arguments(["--unstable", "--list"], {}),
    context,
  )
  assert_eq(
    listed.stdout(),
    b"Available recipes:\n    run [OPTIONS] positional='x'\n",
  )
  let usage = @application.execute_query_command(
    host,
    @cli.parse_arguments(["--unstable", "--usage", "run"], {}),
    context,
  )
  assert_eq(
    usage.stdout(),
    b"Usage: just run [OPTIONS] [positional]\n\nArguments:\n  [positional] [default: 'x']\n\nOptions:\n      --flag toggle\n  -i item [pattern: 'one' | 'two']\n",
  )
}

///|
test "run commands validate invocation before the executor boundary" {
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
    _ => fail("expected executor boundary")
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
    _ => fail("expected executor boundary")
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
    @cli.parse_arguments(
      ["--set", "bad::", "secret-value", "build", "--target"],
      {},
    )
  catch {
    Config(message) =>
      assert_eq(message, "error: invalid override path `bad::`")
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

///|
test "jobs must be a positive integer before execution planning" {
  for value in ["0", "-1", "many"] {
    try @cli.parse_arguments(["--jobs", value, "build"], {}) catch {
      Invalid(message) => assert_true(message.contains("--jobs <N>"))
      error => fail("unexpected jobs parse error: \{Repr(error)}")
    } noraise {
      _ => fail("expected invalid jobs parse rejection")
    }
  }
}

///|
async test "clean removes recognized manifests and reports upstream count" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"build:\n")
  let directory = @path.PathValue::new("/workspace/.justcache", Unix)
  host.put_file(directory, b"")
  let digest = "a".repeat(64)
  host.seed_cache_manifest(directory, digest, b"manifest")
  let response = try! @application.execute_clean_command(
    host,
    try! @cli.parse_arguments(["--clean"], {}),
    context,
  )
  assert_eq(response.stderr(), b"removed 1 cache entry\n")
  assert_eq(host.cache_manifest(directory, digest), None)
  let quiet = try! @application.execute_clean_command(
    host,
    try! @cli.parse_arguments(["--quiet", "--clean"], {}),
    context,
  )
  assert_eq(quiet.stderr(), b"")
  let (missing_host, missing_context) = fake_context()
  missing_host.put_file(file, b"build:\n")
  let missing = try! @application.execute_clean_command(
    missing_host,
    try! @cli.parse_arguments(["--clean"], {}),
    missing_context,
  )
  assert_eq(missing.stderr(), b"recipe cache not found\n")
}

///|
async test "clean filters recipe and module prefixes" {
  let (host, context) = fake_context()
  host.put_file(@path.PathValue::new("/workspace/justfile", Unix), b"build:\n")
  let directory = @path.PathValue::new("/workspace/.justcache", Unix)
  host.put_file(directory, b"")
  for
    entry in [
      ("a".repeat(64), "foo"),
      ("b".repeat(64), "foo::bar"),
      ("c".repeat(64), "foobar"),
    ] {
    let digest = entry.0
    let recipe = entry.1
    let manifest = try! @cache.CacheManifest::new(digest, recipe, [])
    host.seed_cache_manifest(directory, digest, @utf8.encode(manifest.encode()))
  }
  host.seed_cache_manifest(directory, "d".repeat(64), b"")
  let response = try! @application.execute_clean_command(
    host,
    try! @cli.parse_arguments(["--clean", "foo"], {}),
    context,
  )
  assert_eq(response.stderr(), b"removed 3 cache entries\n")
  assert_eq(host.cache_manifest(directory, "a".repeat(64)), None)
  assert_eq(host.cache_manifest(directory, "b".repeat(64)), None)
  assert_eq(host.cache_manifest(directory, "d".repeat(64)), None)
  assert_true(host.cache_manifest(directory, "c".repeat(64)) is Some(_))
}

///|
async test "cache attributes require the explicit unstable gate" {
  let (host, context) = fake_context()
  host.put_file(
    @path.PathValue::new("/workspace/justfile", Unix),
    b"[cache]\n[script]\nbuild:\n  echo cached\n",
  )
  try
    @application.plan_run_command_async(
      host,
      host,
      host,
      try! @cli.parse_arguments(["build"], {}),
      context,
    )
  catch {
    Executor(InvalidAttributeValue(message~, ..)) =>
      assert_true(message.contains("--unstable"))
    error => fail("unexpected cache gate error: \{Repr(error)}")
  } noraise {
    _ => fail("expected cache unstable gate")
  }
  let plan = try! @application.plan_run_command_async(
    host,
    host,
    host,
    try! @cli.parse_arguments(["--unstable", "build"], {}),
    context,
  )
  assert_true(plan.tasks()[0].cache() is Some(_))
}

///|
async test "cache expressions resolve in recipe scope and require scripts" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(
    file, b"[cache(extra=mode, inputs=input, outputs=output)]\n[script]\nbuild input output mode:\n  echo cached\n",
  )
  let plan = try! @application.plan_run_command_async(
    host,
    host,
    host,
    try! @cli.parse_arguments(
      ["--unstable", "build", "source", "artifact", "release"],
      {},
    ),
    context,
  )
  let directive = plan.tasks()[0].cache().unwrap()
  assert_eq(directive.inputs(), ["source"])
  assert_eq(directive.outputs(), ["artifact"])
  assert_eq(directive.extra(), "release")
  let debug = "\{Repr(directive)}"
  assert_true(debug.contains("body_bytes"))
  assert_false(debug.contains("echo cached"))
  assert_false(debug.contains("release"))

  host.put_file(file, b"[cache]\nbuild:\n  echo shell\n")
  try
    @application.plan_run_command_async(
      host,
      host,
      host,
      try! @cli.parse_arguments(["--unstable", "build"], {}),
      context,
    )
  catch {
    Semantic(ScriptAttributeOnShellRecipe(attribute="cache", ..)) => ()
    error => fail("unexpected cache script error: \{Repr(error)}")
  } noraise {
    _ => fail("expected cache script requirement")
  }
}

///|
async test "confirmation plan preserves parent-first dependency context and prompts" {
  let (host, context) = fake_context()
  host.put_file(
    @path.PathValue::new("/workspace/justfile", Unix),
    b"target := 'production'\n[confirm('Deploy ' + target + '?')]\nroot: (dep 'staging')\n  @echo root\n\n[confirm(if is_dependency() == 'true' { 'dep ' + target + '?' } else { 'direct?' })]\ndep target:\n  @echo dep\n",
  )
  let plan = try! @application.plan_run_command_async(
    host,
    host,
    host,
    try! @cli.parse_arguments(["root"], {}),
    context,
  )
  assert_eq(plan.confirmations().length(), 2)
  assert_eq(plan.confirmations()[0].recipe(), "root")
  assert_eq(plan.confirmations()[0].prompt(), "Deploy production?")
  assert_false(plan.confirmations()[0].is_dependency())
  assert_eq(plan.confirmations()[1].recipe(), "dep")
  assert_eq(plan.confirmations()[1].prompt(), "dep staging?")
  assert_true(plan.confirmations()[1].is_dependency())
  assert_true(@executor.confirmation_answer_is_yes(" YES\r\n"))
  assert_false(@executor.confirmation_answer_is_yes("true"))
}

///|
test "confirm attributes format and reject excess prompt arguments" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"[confirm('prompt')]\nfoo:\n")
  let dumped = @application.execute_inspect_command(
    host,
    try! @cli.parse_arguments(["--dump"], {}),
    context,
  )
  assert_eq(dumped.stdout(), b"[confirm('prompt')]\nfoo:\n")
  host.put_file(file, b"[confirm('A', 'B')]\nfoo:\n")
  try
    @application.execute_inspect_command(
      host,
      try! @cli.parse_arguments(["--dump"], {}),
      context,
    )
  catch {
    Load(Parse(error) | ParseSource(error, ..)) =>
      assert_eq(
        error.message(),
        "attribute `confirm` got 2 arguments but takes at most 1 argument",
      )
    error => fail("unexpected confirm arity error: \{Repr(error)}")
  } noraise {
    _ => fail("expected excess confirm prompt failure")
  }
}

///|
async test "editor uses visual precedence and opens invalid source from its directory" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"this is not valid just syntax")
  host.set_env("VISUAL", "visual-editor")
  host.set_env("EDITOR", "ignored-editor")
  let expected = try! @host.CommandSpec::new("visual-editor", [
    "/workspace/justfile",
  ])
  expected.set_cwd(@path.PathValue::new("/workspace", Unix))
  expected.set_inherit_stdin(true)
  expected.set_stdout(Inherit)
  expected.set_stderr(Inherit)
  host.expect_process(expected, @host.ProcessResult::new(0, b"", b""))
  let response = try! @application.execute_edit_command_async(
    host,
    host,
    host,
    try! @cli.parse_arguments(["--edit"], {}),
    context,
  )
  assert_eq(response.exit_code(), 0)
  assert_eq(host.pending_process_expectations(), 0)
}

///|
async test "editor falls back through EDITOR and vim" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/tasks.just", Unix)
  host.put_file(file, b"invalid source")
  host.set_env("EDITOR", "configured-editor")
  let configured = try! @host.CommandSpec::new("configured-editor", [
    "/workspace/tasks.just",
  ])
  configured.set_cwd(@path.PathValue::new("/workspace", Unix))
  configured.set_inherit_stdin(true)
  configured.set_stdout(Inherit)
  configured.set_stderr(Inherit)
  host.expect_process(configured, @host.ProcessResult::new(0, b"", b""))
  ignore(
    try! @application.execute_edit_command_async(
      host,
      host,
      host,
      try! @cli.parse_arguments(["--edit", "--justfile-name", "tasks.just"], {}),
      context,
    ),
  )
  assert_eq(host.pending_process_expectations(), 0)
  let (fallback_host, fallback_context) = fake_context()
  fallback_host.put_file(file, b"invalid source")
  let fallback = try! @host.CommandSpec::new("vim", ["/workspace/tasks.just"])
  fallback.set_cwd(@path.PathValue::new("/workspace", Unix))
  fallback.set_inherit_stdin(true)
  fallback.set_stdout(Inherit)
  fallback.set_stderr(Inherit)
  fallback_host.expect_process(fallback, @host.ProcessResult::new(0, b"", b""))
  ignore(
    try! @application.execute_edit_command_async(
      fallback_host,
      fallback_host,
      fallback_host,
      try! @cli.parse_arguments(["--edit", "--justfile-name", "tasks.just"], {}),
      fallback_context,
    ),
  )
  assert_eq(fallback_host.pending_process_expectations(), 0)
}

///|
async test "interactive invocation and exit failures retain context" {
  let (host, context) = fake_context()
  host.put_file(@path.PathValue::new("/workspace/justfile", Unix), b"build:\n")
  host.set_env("VISUAL", "broken-editor")
  try
    @application.execute_edit_command_async(
      host,
      host,
      host,
      try! @cli.parse_arguments(["--edit"], {}),
      context,
    )
  catch {
    error => {
      assert_eq(error.exit_code(), 1)
      assert_true(
        error.message().contains("editor `broken-editor` invocation failed"),
      )
    }
  } noraise {
    _ => fail("expected editor invocation failure")
  }
  let editor = try! @host.CommandSpec::new("broken-editor", [
    "/workspace/justfile",
  ])
  editor.set_cwd(@path.PathValue::new("/workspace", Unix))
  editor.set_inherit_stdin(true)
  editor.set_stdout(Inherit)
  editor.set_stderr(Inherit)
  host.expect_process(editor, @host.ProcessResult::new(2, b"", b""))
  try
    @application.execute_edit_command_async(
      host,
      host,
      host,
      try! @cli.parse_arguments(["--edit"], {}),
      context,
    )
  catch {
    error => {
      assert_eq(error.exit_code(), 2)
      assert_true(error.message().contains("editor `broken-editor` failed"))
    }
  } noraise {
    _ => fail("expected editor exit failure")
  }
}

///|
async test "chooser filters candidates and preserves each selected invocation" {
  let (host, context) = fake_context()
  host.put_file(
    @path.PathValue::new("/workspace/justfile", Unix),
    b"mode := 'local'\n[group('ci')]\nfirst:\n  @echo {{mode}}\n\n[group('ci')]\nvariadic *args:\n  @echo {{args}}\n\nrequires arg:\n  @echo {{arg}}\n\n[private]\nsecret:\n\n_hidden:\n",
  )
  host.set_env("JUST_CHOOSER", "cat")
  let expected = try! @host.CommandSpec::new("sh", ["-cu", "cat"])
  expected.set_cwd(@path.PathValue::new("/workspace", Unix))
  expected.set_stdin(b"first\nvariadic\n")
  expected.set_stdout(Capture)
  expected.set_stderr(Inherit)
  host.expect_process(
    expected,
    @host.ProcessResult::new(0, b"first\nvariadic one two\n", b""),
  )
  let arguments = try! @cli.parse_arguments(
    ["--choose", "--group", "ci", "--set", "mode", "release"],
    {},
  )
  let selections = try! @application.execute_choose_command_async(
    host, host, host, arguments, context,
  )
  assert_eq(selections, [["first"], ["variadic", "one", "two"]])
  assert_eq(
    arguments.with_run_positionals(selections[0]).variable_overrides(),
    [("mode", "release")],
  )
  assert_eq(host.pending_process_expectations(), 0)
}

///|
async test "chooser rejects an empty public zero-argument candidate set" {
  let (host, context) = fake_context()
  host.put_file(
    @path.PathValue::new("/workspace/justfile", Unix),
    b"_private:\n\nrequired argument:\n",
  )
  try
    @application.execute_choose_command_async(
      host,
      host,
      host,
      try! @cli.parse_arguments(["--choose"], {}),
      context,
    )
  catch {
    Query(message) =>
      assert_eq(message, "justfile contains no choosable recipes")
    error => fail("unexpected empty chooser error: \{Repr(error)}")
  } noraise {
    _ => fail("expected no chooser candidates")
  }
  assert_eq(host.process_calls().length(), 0)
}

///|
async test "default chooser is deterministic and source-aware" {
  let (host, context) = fake_context()
  host.put_file(@path.PathValue::new("/workspace/justfile", Unix), b"build:\n")
  let command = "fzf --multi --preview 'just --unstable --color always --justfile \"/workspace/justfile\" --show {}'"
  let expected = try! @host.CommandSpec::new("sh", ["-cu", command])
  expected.set_cwd(@path.PathValue::new("/workspace", Unix))
  expected.set_stdin(b"build\n")
  expected.set_stdout(Capture)
  expected.set_stderr(Inherit)
  host.expect_process(expected, @host.ProcessResult::new(130, b"", b""))
  assert_eq(
    try! @application.execute_choose_command_async(
      host,
      host,
      host,
      try! @cli.parse_arguments(["--choose"], {}),
      context,
    ),
    [],
  )
}

///|
async test "chooser cancellation succeeds and signals preserve exit status" {
  let (host, context) = fake_context()
  host.put_file(@path.PathValue::new("/workspace/justfile", Unix), b"build:\n")
  let cancelled = try! @host.CommandSpec::new("sh", ["-cu", "cancel"])
  cancelled.set_cwd(@path.PathValue::new("/workspace", Unix))
  cancelled.set_stdin(b"build\n")
  cancelled.set_stdout(Capture)
  cancelled.set_stderr(Inherit)
  host.expect_process(cancelled, @host.ProcessResult::new(130, b"", b""))
  let cancelled_arguments = try! @cli.parse_arguments(
    ["--choose", "--chooser", "cancel"],
    {},
  )
  assert_eq(
    try! @application.execute_choose_command_async(
      host, host, host, cancelled_arguments, context,
    ),
    [],
  )
  let signaled = try! @host.CommandSpec::new("sh", ["-cu", "signal"])
  signaled.set_cwd(@path.PathValue::new("/workspace", Unix))
  signaled.set_stdin(b"build\n")
  signaled.set_stdout(Capture)
  signaled.set_stderr(Inherit)
  host.expect_process(
    signaled,
    @host.ProcessResult::from_signal(Terminate, b"", b""),
  )
  try
    @application.execute_choose_command_async(
      host,
      host,
      host,
      try! @cli.parse_arguments(["--choose", "--chooser", "signal"], {}),
      context,
    )
  catch {
    error => {
      assert_eq(error.exit_code(), 143)
      assert_eq(
        error.message(),
        "error: chooser `signal` failed: signal: 15 (SIGTERM)",
      )
    }
  } noraise {
    _ => fail("expected chooser signal failure")
  }
}

///|
async test "chooser nonzero status is propagated" {
  let (host, context) = fake_context()
  host.put_file(@path.PathValue::new("/workspace/justfile", Unix), b"build:\n")
  let failed = try! @host.CommandSpec::new("sh", ["-cu", "fail"])
  failed.set_cwd(@path.PathValue::new("/workspace", Unix))
  failed.set_stdin(b"build\n")
  failed.set_stdout(Capture)
  failed.set_stderr(Inherit)
  host.expect_process(failed, @host.ProcessResult::new(2, b"", b""))
  try
    @application.execute_choose_command_async(
      host,
      host,
      host,
      try! @cli.parse_arguments(["--choose", "--chooser", "fail"], {}),
      context,
    )
  catch {
    error => {
      assert_eq(error.exit_code(), 2)
      assert_true(error.message().contains("chooser `fail` failed"))
    }
  } noraise {
    _ => fail("expected chooser status failure")
  }
}

///|
async test "command color follows forced auto never and explicit color modes" {
  let (host, context) = fake_context()
  host.put_file(
    @path.PathValue::new("/workspace/justfile", Unix),
    b"build:\n  echo ok\n",
  )
  host.set_terminal(@host.TerminalInfo::new(false, false, false, false))
  let automatic = try! @application.plan_run_command_async(
    host,
    host,
    host,
    try! @cli.parse_arguments(["build"], {}),
    context,
  )
  assert_eq(automatic.options().command_color(), None)
  let forced = try! @application.plan_run_command_async(
    host,
    host,
    host,
    try! @cli.parse_arguments(["--color", "always", "build"], {}),
    context,
  )
  assert_eq(forced.options().command_color(), Some(Bold))
  assert_true(forced.options().color_enabled())
  assert_eq(
    @executor.render_command_echo(
      "echo ok",
      color=forced.options().command_color(),
    ),
    b"\x1b[1mecho ok\x1b[0m\n",
  )
  let purple = try! @application.plan_run_command_async(
    host,
    host,
    host,
    try! @cli.parse_arguments(
      ["--color", "always", "--command-color", "purple", "build"],
      {},
    ),
    context,
  )
  assert_eq(purple.options().command_color(), Some(Magenta))
  assert_eq(
    @executor.render_command_echo(
      "echo ok",
      color=purple.options().command_color(),
    ),
    b"\x1b[1;35mecho ok\x1b[0m\n",
  )
  host.set_terminal(@host.TerminalInfo::new(false, false, true, true))
  let disabled = try! @application.plan_run_command_async(
    host,
    host,
    host,
    try! @cli.parse_arguments(["--color", "never", "build"], {}),
    context,
  )
  assert_eq(disabled.options().command_color(), None)
  assert_false(disabled.options().color_enabled())
  let no_highlight = try! @application.plan_run_command_async(
    host,
    host,
    host,
    try! @cli.parse_arguments(
      ["--color", "always", "--no-highlight", "build"],
      {},
    ),
    context,
  )
  assert_eq(no_highlight.options().command_color(), None)
  assert_true(no_highlight.options().color_enabled())
}
