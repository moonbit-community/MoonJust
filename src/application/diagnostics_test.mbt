///|
test "application coverage exercises stable error presentation families" {
  let source = @source.Source::from_text(
    @source.SourceId::new(9900),
    "application.just",
    "x\n",
  )
  let span = source.full_span()
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let evaluation = @evaluator.EvaluationError::UndefinedVariable(
    name="x",
    span~,
  )
  let semantic = @semantic.SemanticError::UndefinedVariable(name="x", span~)
  let errors : Array[@application.ApplicationError] = [
    Cli(Invalid("bad")),
    Cli(Config("config")),
    Cli(Unsupported("future")),
    Load(InvalidLimit),
    Format(InvalidInput("format")),
    Evaluation(evaluation),
    Environment(EmptyShell),
    Dotenv(Required),
    Executor(UnknownRecipe(recipe="missing")),
    Host(InvalidInput("host")),
    Invocation(NoRecipes),
    Path(NulByte),
    Project(MissingRootModule),
    Semantic(semantic),
    ContextualSemantic(error=semantic, source~, cwd~),
    WorkingDirectory(JustfileWithoutParent(cwd)),
    InteractiveInvocation(kind="command", command="tool", detail="missing"),
    InteractiveInvocation(kind="shell", command="sh", detail="missing"),
    InteractiveProcess(kind="command", command="tool", termination=Exited(3)),
    InteractiveProcess(
      kind="shell",
      command="sh",
      termination=Signaled(Terminate),
    ),
    InteractiveProcess(
      kind="shell",
      command="sh",
      termination=Interrupted(Interrupt),
    ),
    DotenvCommand(command="dotenv", exit_code=4),
    WriteJustfile(path=cwd, detail="denied"),
    AlreadyExists(cwd),
    Query("query"),
    UnsupportedCommand("feature"),
  ]
  for error in errors {
    assert_true(error.message().length() > 0)
    assert_true(error.exit_code() >= 0)
  }
}

///|
test "application coverage renders source and fallback diagnostics" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"value := missing\nroot:\n")
  let source = @source.Source::from_text(
    @source.SourceId::new(9901),
    "justfile",
    "value := missing\nroot:\n",
  )
  let span = source.full_span()
  let arguments = try! @cli.parse_arguments([], {})
  let errors : Array[@application.ApplicationError] = [
    Semantic(UndefinedVariable(name="missing", span~)),
    ContextualSemantic(
      error=UndefinedVariable(name="missing", span~),
      source~,
      cwd=@path.PathValue::new("/workspace", Unix),
    ),
    Evaluation(UndefinedVariable(name="missing", span~)),
    Executor(Evaluation(UndefinedVariable(name="missing", span~))),
    Load(InvalidLimit),
    Invocation(UnknownRecipe(recipe="missing")),
  ]
  for error in errors {
    let rendered = @application.render_application_error(
      host, arguments, context, error,
    )
    assert_true(rendered.length() > 0)
  }
  let fallback = @application.render_application_error(
    host,
    arguments,
    context,
    Query("plain query"),
  )
  assert_eq(fallback, "error: plain query")
}

///|
async test "application coverage renders direct evaluation contracts synchronously and asynchronously" {
  let (host, context) = fake_context()
  let arguments = try! @cli.parse_arguments([], {})
  let span = @source.Span::origin(@source.SourceId::new(9905))
  let errors : Array[@application.ApplicationError] = [
    Evaluation(UnknownOverrides(names=["missing"], span~)),
    Evaluation(EmptyParameter(recipe="build", parameter="target", span~)),
    Executor(
      Evaluation(EmptyParameter(recipe="build", parameter="target", span~)),
    ),
    Evaluation(FunctionRecursionLimit(name="f", limit=8, span~)),
  ]
  for error in errors {
    let rendered = @application.render_application_error(
      host, arguments, context, error,
    )
    assert_true(rendered.contains("error:"))
    let async_rendered = @application.render_application_error_async(
      host, arguments, context, error,
    )
    assert_eq(async_rendered, rendered)
  }
}

///|
async test "application coverage executes arbitrary command contracts" {
  let (host, context) = fake_context()
  host.put_file(
    @path.PathValue::new("/workspace/justfile", Unix),
    b"set export\nMODE := 'ci'\nroot:\n",
  )
  let direct = try! @host.CommandSpec::new("tool", ["one", "two"])
  direct.set_cwd(@path.PathValue::new("/workspace", Unix))
  direct.set_inherit_environment(false)
  try! direct.add_environment("MODE", "ci")
  direct.set_inherit_stdin(true)
  direct.set_stdout(Inherit)
  direct.set_stderr(Inherit)
  host.expect_process(direct, @host.ProcessResult::new(0, b"", b""))
  let response = try! @application.execute_command_command_async(
    host,
    host,
    host,
    try! @cli.parse_arguments(["--command", "tool", "one", "two"], {}),
    context,
  )
  assert_eq(response.exit_code(), 0)
  assert_eq(host.pending_process_expectations(), 0)

  let shell = try! @host.CommandSpec::new("sh", ["-cu", "echo hello"])
  shell.set_cwd(@path.PathValue::new("/workspace", Unix))
  shell.set_inherit_environment(false)
  try! shell.add_environment("MODE", "ci")
  shell.set_inherit_stdin(true)
  shell.set_stdout(Discard)
  shell.set_stderr(Discard)
  host.expect_process(shell, @host.ProcessResult::new(7, b"", b""))
  try
    @application.execute_command_command_async(
      host,
      host,
      host,
      try! @cli.parse_arguments(
        ["--command", "--shell-command", "--quiet", "echo", "hello"],
        {},
      ),
      context,
    )
  catch {
    InteractiveProcess(termination=Exited(7), ..) => ()
    error => fail("unexpected command failure: \{Repr(error)}")
  } noraise {
    _ => fail("expected command exit failure")
  }
  assert_eq(host.pending_process_expectations(), 0)

  try
    @application.execute_command_command_async(
      host,
      host,
      host,
      try! @cli.parse_arguments(["--list"], {}),
      context,
    )
  catch {
    UnsupportedCommand(_) => ()
    error => fail("unexpected non-command error: \{Repr(error)}")
  } noraise {
    _ => fail("expected non-command rejection")
  }
}

///|
async test "application coverage renders asynchronous source diagnostics" {
  let (host, context) = fake_context()
  let file = try! @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"value := missing\nroot:\n")
  let source = @source.Source::from_text(
    @source.SourceId::new(9902),
    "justfile",
    "value := missing\nroot:\n",
  )
  let span = source.full_span()
  let arguments = try! @cli.parse_arguments([], {})
  let errors : Array[@application.ApplicationError] = [
    Semantic(UndefinedVariable(name="missing", span~)),
    ContextualSemantic(
      error=UndefinedVariable(name="missing", span~),
      source~,
      cwd=try! @path.PathValue::new("/workspace", Unix),
    ),
    Evaluation(UndefinedVariable(name="missing", span~)),
    Executor(Evaluation(UndefinedVariable(name="missing", span~))),
    Invocation(UnknownRecipe(recipe="missing")),
    Query("plain asynchronous query"),
  ]
  for error in errors {
    let rendered = @application.render_application_error_async(
      host, arguments, context, error,
    )
    assert_true(rendered.length() > 0)
  }
}

///|
async test "application coverage exercises asynchronous query and inspect commands" {
  let (host, context) = fake_context()
  let file = try! @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(
    file, b"set lists\nvalue := 'ci'\n[arg('flag', long, flag, help='toggle')]\n[arg('item', short, pattern=['one', 'two'])]\n[group('build')]\nrun flag item positional='x':\n  echo {{value}}\n",
  )
  for
    row in [
      (["--unstable", "--list"], "run"),
      (["--unstable", "--summary"], "run"),
      (["--unstable", "--variables"], "value"),
      (["--unstable", "--groups"], "build"),
      (["--unstable", "--show", "run"], "run"),
      (["--unstable", "--usage", "run"], "Usage"),
    ] {
    let response = try! @application.execute_query_command_with_terminal_async(
      host,
      host,
      try! @cli.parse_arguments(row.0, {}),
      context,
    )
    assert_true((try! @utf8.decode(response.stdout())).contains(row.1))
  }
  for
    arguments in [
      ["--unstable", "--json"],
      ["--unstable", "--dump", "--dump-format", "json"],
      ["--unstable", "--dump"],
      ["--unstable", "--evaluate", "value"],
    ] {
    let response = try! @application.execute_inspect_command_async(
      host,
      try! @cli.parse_arguments(arguments, {}),
      context,
    )
    assert_true(response.stdout().length() > 0)
  }
}

///|
async test "application coverage exercises default list sync and async" {
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  host.set_terminal(@host.TerminalInfo::new(true, true, true, true))
  host.put_file(
    try! @path.PathValue::new("/workspace/justfile", Unix),
    b"set default-list\n[group('ci')]\nbuild:\n",
  )
  let context = @application.ApplicationContext::new(cwd)
  let arguments = try! @cli.parse_arguments([], {})
  assert_true(
    (try! @application.execute_default_list_command(
      host, host, arguments, context,
    ))
    is Some(_),
  )
  assert_true(
    (try! @application.execute_default_list_command_async(
      host, host, arguments, context,
    ))
    is Some(_),
  )
  assert_eq(
    try! @application.execute_default_list_command(
      host,
      host,
      try! @cli.parse_arguments(["--summary"], {}),
      context,
    ),
    None,
  )
}

///|
test "application coverage plans synchronous recipes and validates plan modes" {
  let (host, context) = fake_context()
  let file = try! @path.PathValue::new("/workspace/justfile", Unix)
  host.set_env("BASE", "ambient")
  host.put_file(
    file, b"set export\nMODE := 'sync'\nrun target='default' *rest='tail':\n  echo {{target}} {{rest}}\nclean:\n  echo clean\n",
  )
  let explicit = try! @application.plan_run_command(
    host,
    host,
    try! @cli.parse_arguments(["run", "chosen", "one", "two"], {}),
    context,
  )
  assert_true(explicit.steps().length() > 0 || explicit.commands().length() > 0)
  let defaults = try! @application.plan_run_command(
    host,
    host,
    try! @cli.parse_arguments(["run"], {}),
    context,
  )
  assert_true(defaults.steps().length() > 0 || defaults.commands().length() > 0)
  try
    @application.plan_run_command(
      host,
      host,
      try! @cli.parse_arguments(["--one", "clean", "run"], {}),
      context,
    )
  catch {
    Query(message) => assert_true(message.contains("expected 1"))
    error => fail("unexpected --one error: \{Repr(error)}")
  } noraise {
    _ => fail("expected --one plan rejection")
  }
  try
    @application.plan_run_command(
      host,
      host,
      try! @cli.parse_arguments(["--list"], {}),
      context,
    )
  catch {
    UnsupportedCommand(_) => ()
    error => fail("unexpected non-run plan error: \{Repr(error)}")
  } noraise {
    _ => fail("expected non-run plan rejection")
  }
  let denied = @host.FakeHost::new(
    try! @path.PathValue::new("/workspace", Unix),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  denied.deny(Environment)
  try
    @application.plan_run_command(
      host,
      denied,
      try! @cli.parse_arguments(["run"], {}),
      context,
    )
  catch {
    Host(CapabilityDenied(Environment)) => ()
    error => fail("unexpected plan environment error: \{Repr(error)}")
  } noraise {
    _ => fail("expected denied plan environment")
  }
}

///|
async test "application coverage lists nested project modules and aliases" {
  let (host, context) = fake_context()
  host.put_file(
    try! @path.PathValue::new("/workspace/justfile", Unix),
    b"[doc('tool module')]\n[group('modules')]\nmod tools 'tools.just'\nroot:\n\nalias tool := tools::task\n",
  )
  host.put_file(
    try! @path.PathValue::new("/workspace/tools.just", Unix),
    b"# nested task\ntask:\n",
  )
  let response = try! @application.execute_query_command_with_terminal_async(
    host,
    host,
    try! @cli.parse_arguments(
      ["--unstable", "--list", "--list-submodules", "--unsorted"],
      {},
    ),
    context,
  )
  let text = try! @utf8.decode(response.stdout())
  assert_true(text.contains("tools:"))
  assert_true(text.contains("task"))
  assert_true(text.contains("tool module"))
}
