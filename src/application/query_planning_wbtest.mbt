///|
fn application_behavior_source() -> @source.Source {
  @source.Source::from_text(
    @source.SourceId::new(9950),
    "behavior.just",
    "set lists\nset export\nset dotenv-filename := ['.env', '.env.local']\n" +
    "set shell := ['sh', '-cu']\n" +
    "_private := 'hidden'\npublic := 'value'\n" +
    "[doc('build docs')]\n[group('ci')]\n[metadata('z', 'a')]\n" +
    "[arg('target', long='target', short='t', help='target help', value='dev', multiple, min='1', max='2', pattern=['dev', 'release'])]\n" +
    "build target='dev' *rest:\n  echo {{target}} {{rest}}\n" +
    "[private]\nsecret:\n  echo secret\n" +
    "alias b := build\n",
  )
}

///|
test "application whitebox behavior exercises inspect JSON and query renderers" {
  let source = application_behavior_source()
  let compilation = try
    @semantic.compile_source(source, allow_unstable=true)
  catch {
    error => fail("behavior source compile failed: \{Repr(error)}")
  } noraise {
    value => value
  }
  let loaded = try! @loader.load_stdin(@utf8.encode(source.text()), source.id())
  let ast = loaded.ast()
  let root = @modulepath.ModulePath::root()
  let docs = recipe_docs(ast)
  assert_true(docs.length() >= 0)
  let build = compilation.recipe("build").unwrap()
  assert_true(recipe_signature(build).contains("OPTIONS"))
  assert_true(styled_recipe_signature(build, true).contains("build"))
  assert_true(private_assignments(ast).contains("_private"))

  let span = source.full_span()
  let literal = @syntax.StringLiteral::new("'text'", "text", Raw, span)
  let argument = fn(key : String?, value : @syntax.Expression?) {
    @syntax.AttributeArgument::new(key, value, span)
  }
  let string_expression = @syntax.Expression::String(literal)
  let rich_arg = @syntax.Attribute::new(
    "arg",
    [
      argument(None, Some(string_expression)),
      argument(Some("help"), None),
      argument(Some("long"), None),
      argument(Some("max"), Some(string_expression)),
      argument(Some("min"), Some(string_expression)),
      argument(Some("pattern"), Some(string_expression)),
      argument(Some("short"), None),
      argument(Some("value"), None),
    ],
    span,
  )
  for
    attribute in [
      @syntax.Attribute::new("arg", [], span),
      @syntax.Attribute::new("arg", [argument(None, None)], span),
      rich_arg,
      @syntax.Attribute::new(
        "continue",
        [argument(None, Some(string_expression)), argument(None, None)],
        span,
      ),
      @syntax.Attribute::new(
        "metadata",
        [argument(None, Some(string_expression))],
        span,
      ),
      @syntax.Attribute::new("private", [], span),
      @syntax.Attribute::new(
        "custom",
        [
          argument(None, Some(string_expression)),
          argument(Some("enabled"), None),
        ],
        span,
      ),
    ] {
    assert_true(attribute_json(attribute).stringify().length() > 0)
  }
  let expressions : Array[@syntax.Expression] = [
    String(literal),
    Backtick(
      @syntax.StringLiteral::new("`echo text`", "echo text", Backtick, span),
    ),
    Boolean(value=true, span~),
    Variable(name="public", span~),
    Call(name="join", arguments=[String(literal), String(literal)], span~),
    List(elements=[String(literal), String(literal)], span~),
    Parenthesized(expression=Boolean(value=true, span~), span~),
    Unary(operator=Not, operand=Boolean(value=true, span~), span~),
    Binary(
      operator=Equal,
      operator_span=span,
      lhs=Boolean(value=true, span~),
      rhs=Boolean(value=false, span~),
      span~,
    ),
    Binary(
      operator=NotEqual,
      operator_span=span,
      lhs=Boolean(value=true, span~),
      rhs=Boolean(value=false, span~),
      span~,
    ),
    Binary(
      operator=RegexMatch,
      operator_span=span,
      lhs=String(literal),
      rhs=String(literal),
      span~,
    ),
    Binary(
      operator=RegexNotMatch,
      operator_span=span,
      lhs=String(literal),
      rhs=String(literal),
      span~,
    ),
    Binary(
      operator=ListConcat,
      operator_span=span,
      lhs=List(elements=[String(literal)], span~),
      rhs=List(elements=[String(literal)], span~),
      span~,
    ),
    Binary(
      operator=Concat,
      operator_span=span,
      lhs=String(literal),
      rhs=String(literal),
      span~,
    ),
    Binary(
      operator=Join,
      operator_span=span,
      lhs=String(literal),
      rhs=String(literal),
      span~,
    ),
    Conditional(
      condition=Boolean(value=true, span~),
      then_branch=String(literal),
      else_branch=Some(String(literal)),
      span~,
    ),
    Format(
      start=@syntax.StringLiteral::new("\"hello \"", "hello ", Cooked, span),
      parts=[@syntax.FormatPart::new(Variable(name="public", span~), literal)],
      span~,
    ),
  ]
  for expression in expressions {
    let json = expression_json(expression)
    assert_true(json.stringify().length() > 0)
  }

  for
    value in [
      Some(
        @syntax.Expression::String(
          @syntax.StringLiteral::new("'7'", "7", Cooked, source.full_span()),
        ),
      ),
      Some(Boolean(value=true, span=source.full_span())),
      None,
    ] {
    assert_true(unsigned_json(value).stringify().length() > 0)
  }
  assert_true(pattern_json(None).stringify().length() > 0)
  assert_true(
    pattern_json(Some(List(elements=[], span=source.full_span())))
    .stringify()
    .length() >
    0,
  )
  assert_true(
    attribute_plain_json(List(elements=[], span=source.full_span()))
    .stringify()
    .length() >
    0,
  )

  let settings = compilation.settings()
  for
    name in [
      "lists", "export", "dotenv-filename", "shell", "indentation", "missing-setting",
    ] {
    assert_true(setting_json(settings, name).stringify().length() > 0)
    assert_true(setting_list_json(settings, name).stringify().length() > 0)
    assert_true(
      setting_scalar_or_list_json(settings, name).stringify().length() > 0,
    )
    assert_true(interpreter_json(settings, name).stringify().length() > 0)
  }
  assert_true(settings_json(settings).stringify().length() > 0)
  assert_true(
    assignment_json(compilation.variable("public").unwrap(), false)
    .stringify()
    .length() >
    0,
  )
  for dependency in build.dependencies() {
    assert_true(dependency_json(dependency).stringify().length() > 0)
  }
  for attribute in build.attributes() {
    assert_true(attribute_json(attribute).stringify().length() > 0)
  }
  for parameter in build.parameters() {
    assert_true(
      parameter_json(parameter, build.attributes())
      .stringify()
      .contains(parameter.name()),
    )
  }
  assert_true(
    recipe_json(build, compilation, docs, root).stringify().length() > 0,
  )
  let inspected = inspect_json(loaded, compilation)
  assert_true(inspected.stringify().contains("recipes"))

  assert_eq(lexical_compare("a", "b"), -1)
  assert_eq(lexical_compare("b", "a"), 1)
  assert_eq(lexical_compare("a", "a"), 0)
  assert_true(edit_distance("build", "buil") >= 0)
  assert_eq(closest_name("buil", ["build", "clean"]), Some("build"))
  assert_eq(closest_name("unknown", ["build"]), None)
  assert_true(alias_names(compilation, "build").contains("b"))
  assert_true(alias_annotation(["b", "build-all"]).contains("alias"))
  assert_eq(paint("text", "31", false), "text")
  assert_true(paint("text", "31", true).contains("31"))
  assert_eq(styled_doc("plain", false), "plain")
  assert_true(styled_doc("`code`", true).contains("code"))
  assert_true(unknown_recipe_message(compilation, "buil").contains("build"))

  let arguments = try! @cli.parse_arguments(["--list", "--unsorted"], {})
  let listed = try! list_text(loaded, compilation, arguments, false)
  assert_true(listed.contains("build"))
  assert_true(show_recipe_text(loaded, compilation, "b").contains("build"))
  let usage = try! usage_recipe_text(compilation, "b", "b")
  assert_true(usage.contains("Usage: just b"))
  assert_true(
    show_text(
      loaded,
      compilation,
      try! @cli.parse_arguments(["--show", "b"], {}),
    ).contains("build"),
  )
  assert_true(
    usage_text(compilation, try! @cli.parse_arguments(["--usage", "b"], {})).contains(
      "Usage",
    ),
  )
}

///|
test "application whitebox behavior exercises query and evaluation edge branches" {
  let source = application_behavior_source()
  let compilation = try! @semantic.compile_source(source, allow_unstable=true)
  let loaded = try! @loader.load_stdin(@utf8.encode(source.text()), source.id())
  let ast = loaded.ast()
  let environment = try! @evaluator.evaluate_compilation(compilation)

  assert_eq(shell_escape("!\"$\\`"), "\\!\\\"\\$\\\\\\`")
  assert_eq(joined_value(String("value")), "value")
  assert_true(just_value(String("value")).contains("value"))
  assert_true(colored_just_value(String("a\\nb")).contains("\u{001b}["))
  assert_eq(
    evaluate_text(
      compilation,
      ast,
      try! @cli.parse_arguments(["--evaluate", "public"], {}),
    ),
    "value",
  )
  assert_true(
    evaluate_text(
      compilation,
      ast,
      try! @cli.parse_arguments(["--evaluate", "--color", "always"], {}),
    ).contains("\u{001b}[32m"),
  )
  assert_true(
    evaluate_text(
      compilation,
      ast,
      try! @cli.parse_arguments(["--evaluate", "--evaluate-format", "shell"], {}),
    ).contains("public=\"value\""),
  )
  assert_eq(
    evaluated_environment_text(
      compilation,
      ast,
      try! @cli.parse_arguments(["--evaluate"], {}),
      environment,
      selected="public",
    ),
    "value",
  )
  try
    evaluated_environment_text(
      compilation,
      ast,
      try! @cli.parse_arguments(["--evaluate"], {}),
      environment,
      selected="missing",
    )
  catch {
    Query(message) => assert_true(message.contains("not defined"))
    error => fail("unexpected selected variable error: \{Repr(error)}")
  } noraise {
    _ => fail("expected selected variable error")
  }
  assert_true(
    evaluated_environment_text(
      compilation,
      ast,
      try! @cli.parse_arguments(["--evaluate", "--color", "always"], {}),
      environment,
    ).contains("\u{001b}[32m"),
  )
  assert_true(
    evaluated_environment_text(
      compilation,
      ast,
      try! @cli.parse_arguments(["--evaluate", "--evaluate-format", "shell"], {}),
      environment,
    ).contains("public=\"value\""),
  )

  let query_cases = [
    (["--list"], "build"),
    (["--summary"], "build"),
    (["--show", "b"], "build"),
    (["--usage", "b"], "Usage"),
    (["--variables"], "public"),
    (["--groups"], "ci"),
  ]
  for row in query_cases {
    assert_true(
      (try! query_text(
        loaded,
        compilation,
        try! @cli.parse_arguments(row.0, {}),
        false,
      )).contains(row.1),
    )
  }
  let empty_source = @source.Source::from_text(
    @source.SourceId::new(9951),
    "empty.just",
    "_private := 'hidden'\n",
  )
  let empty_compilation = try! @semantic.compile_source(empty_source)
  let empty_loaded = try! @loader.load_stdin(
    @utf8.encode(empty_source.text()),
    empty_source.id(),
  )
  assert_eq(
    try! query_text(
      empty_loaded,
      empty_compilation,
      try! @cli.parse_arguments(["--variables"], {}),
      false,
    ),
    "",
  )
  assert_eq(
    try! query_text(
      empty_loaded,
      empty_compilation,
      try! @cli.parse_arguments(["--groups"], {}),
      false,
    ),
    "",
  )
  for
    arguments in [
      ["--show"],
      ["--show", "build", "extra"],
      ["--usage"],
      ["--usage", "build", "extra"],
      ["--groups", "extra"],
    ] {
    try
      query_text(
        loaded,
        compilation,
        try! @cli.parse_arguments(arguments, {}),
        false,
      )
    catch {
      Query(message) => assert_true(message.length() > 0)
      error => fail("unexpected query edge error: \{Repr(error)}")
    } noraise {
      _ => fail("expected query edge error")
    }
  }
  try
    query_text(loaded, compilation, try! @cli.parse_arguments([], {}), false)
  catch {
    UnsupportedCommand(_) => ()
    error => fail("unexpected unsupported query error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unsupported query error")
  }

  assert_eq(alias_annotation(["b"]), "[alias: b]")
  assert_true(styled_doc("plain `code` tail", true).contains("36m"))
  assert_true(styled_doc("plain `open", true).contains("open"))
  let builder = StringBuilder()
  write_list_line(builder, "  ", "build", ["docs"], 8, true)
  assert_true(builder.to_string().contains("docs"))
  let row = ListRow::{
    name: "build",
    signature: "build target",
    rendered_signature: "build target",
    doc: Some("docs"),
    aliases: ["b"],
    groups: ["ci"],
    nested: None,
  }
  assert_eq(alias_signature(row, "b"), "b target")
  assert_eq(rendered_alias_signature(row, "b"), "b target")
  assert_eq(display_width("\t"), 1)

  let project = @semantic.ProjectCompilation::from_root(
    compilation,
    try! @path.PathValue::new("/workspace", Unix),
  )
  assert_eq(
    default_list_module_path(project, []),
    Some(@modulepath.ModulePath::root()),
  )
  assert_true(
    project_summary_text(project, try! @cli.parse_arguments(["--summary"], {})).contains(
      "build",
    ),
  )
  assert_eq(
    evaluation_path(project, ["public"]),
    (@modulepath.ModulePath::root(), Some("public")),
  )
}

///|
fn application_behavior_project(text : String) -> @semantic.ProjectCompilation {
  let compilation = try! @semantic.compile_source(
    @source.Source::from_text(@source.SourceId::new(9960), "project.just", text),
    allow_unstable=true,
  )
  @semantic.ProjectCompilation::from_root(
    compilation,
    try! @path.PathValue::new("/workspace", Unix),
  )
}

///|
test "application whitebox behavior exercises argument routing helpers" {
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let context = ApplicationContext::new(cwd, stdin=b"root:\n")
  let search = try! @cli.parse_arguments([], {})
  assert_eq(input_selection(search, Unix), Search)
  assert_eq(working_directory_argument(search, Unix), None)
  assert_eq(ceiling_argument(search, cwd), None)

  let stdin = try! @cli.parse_arguments(["--justfile", "-"], {})
  assert_eq(input_selection(stdin, Unix), Stdin)
  let file = try! @cli.parse_arguments(
    [
      "--justfile", "tasks.just", "--working-directory", "build", "--ceiling", "project",
    ],
    {},
  )
  assert_true(input_selection(file, Unix) is File(_))
  assert_eq(
    working_directory_argument(file, Unix).unwrap().as_string(),
    "build",
  )
  assert_eq(
    ceiling_argument(file, cwd).unwrap().as_string(),
    "/workspace/project",
  )

  let (plain, plain_context) = search_prefixed_invocation(
    try! @cli.parse_arguments(["build"], {}),
    context,
  )
  assert_eq(plain.positional(), ["build"])
  assert_eq(plain_context.cwd(), cwd)
  let (prefixed, prefixed_context) = search_prefixed_invocation(
    try! @cli.parse_arguments(["sub/build", "arg"], {}),
    context,
  )
  assert_eq(prefixed.positional(), ["build", "arg"])
  assert_eq(prefixed_context.cwd().as_string(), "/workspace/sub")
  let (directory, directory_context) = search_prefixed_invocation(
    try! @cli.parse_arguments(["sub/"], {}),
    context,
  )
  assert_eq(directory.positional(), [])
  assert_eq(directory_context.cwd().as_string(), "/workspace/sub")

  try global_input_directories(context) catch {
    Query(message) => assert_true(message.contains("global justfile"))
    error => fail("unexpected global context error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing global context")
  }
  let global_context = context.with_global_justfile(
    try! @path.PathValue::new("/config/justfile", Unix),
    try! @path.PathValue::new("/workspace/project", Unix),
  )
  let global_directories = try! global_input_directories(global_context).1
  assert_eq(
    global_directories.project_directory().as_string(),
    "/workspace/project",
  )
}

///|
test "application whitebox behavior exercises planning selections" {
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  host.set_terminal(@host.TerminalInfo::new(true, false, true, true))
  assert_true(
    try! selected_color_active(
      host,
      try! @cli.parse_arguments(["--color", "always"], {}),
    ),
  )
  assert_false(
    try! selected_color_active(
      host,
      try! @cli.parse_arguments(["--color", "never"], {}),
    ),
  )
  assert_true(
    try! selected_color_active(host, try! @cli.parse_arguments([], {})),
  )
  for
    row in [
      ("black", @executor.Black),
      ("red", Red),
      ("green", Green),
      ("yellow", Yellow),
      ("blue", Blue),
      ("purple", Magenta),
      ("cyan", Cyan),
    ] {
    let name = row.0
    let expected = row.1
    let arguments = try! @cli.parse_arguments(
      ["--color", "always", "--command-color", name],
      {},
    )
    assert_eq(try! selected_command_color(arguments, true), Some(expected))
  }
  assert_eq(
    try! selected_command_color(try! @cli.parse_arguments([], {}), false),
    None,
  )
  assert_eq(
    try! selected_command_color(
      try! @cli.parse_arguments(["--no-highlight"], {}),
      true,
    ),
    None,
  )
  assert_eq(try! selected_jobs(try! @cli.parse_arguments([], {})), 1)
  assert_eq(
    try! selected_jobs(try! @cli.parse_arguments(["--jobs", "3"], {})),
    3,
  )
  let options = try! execution_options(
    try! @cli.parse_arguments(
      [
        "--dry-run", "--verbose", "--no-cache", "--no-deps", "--explain", "--jobs",
        "2",
      ],
      {},
    ),
    Some("12:00"),
    Some(Cyan),
    true,
  )
  assert_true(options.dry_run())
  assert_eq(options.jobs(), 2)
  assert_false(options.cache_enabled())
  assert_true(options.no_dependencies())
  assert_true(options.explain())
  assert_eq(try! cache_directory(cwd).as_string(), "/workspace/.justcache")

  let project = application_behavior_project("root:\n")
  let directories = try! @workdir.WorkingDirectoryModel::from_stdin(cwd)
  assert_eq(
    try! project_module_base(
      project,
      directories,
      @modulepath.ModulePath::root(),
    ),
    cwd,
  )
  assert_eq(
    try! project_module_cwd(
      project,
      directories,
      @modulepath.ModulePath::root(),
      None,
      false,
    ),
    cwd,
  )
  assert_eq(
    try! project_module_cwd(
      project,
      directories,
      @modulepath.ModulePath::root(),
      Some("sub"),
      false,
    ).as_string(),
    "/workspace/sub",
  )
  assert_eq(
    try! project_module_cwd(
      project,
      directories,
      @modulepath.ModulePath::root(),
      Some("sub"),
      true,
    ),
    cwd,
  )
}

///|
test "application whitebox behavior exercises global format and interactive helpers" {
  let cwd = try! @path.PathValue::new("/workspace/project/sub", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  host.set_env("HOME", "/home/test")
  assert_eq(
    try! global_child(cwd, ["a", "b"]).as_string(),
    "/workspace/project/sub/a/b",
  )
  assert_eq(
    try! global_environment_path(host, "HOME", Unix).unwrap().as_string(),
    "/home/test",
  )
  assert_eq(try! global_environment_path(host, "MISSING", Unix), None)
  host.put_file(
    try! @path.PathValue::new("/workspace/project/sub/.git", Unix),
    b"",
  )
  assert_eq(try! global_project_root(host, cwd, None), cwd)
  assert_eq(
    try! find_global_candidate(host, [(cwd, ".git")]),
    Some(try! @path.PathValue::new("/workspace/project/sub/.git", Unix)),
  )

  assert_true(format_diff("a\n", "b\n", false).contains("-a\n+b"))
  assert_true(format_diff("a\n", "b\n", true).contains("\u{001b}[31m"))
  assert_true(format_diff("a\nb\n", "a\n", false).contains("-b"))
  assert_true(format_diff("a\n", "a\nb\n", false).contains("+b"))
  assert_true(write_permission_detail(cwd).contains("Permission denied"))
  assert_true(write_directory_detail(cwd).contains("directory"))
  let windows = try! @path.PathValue::new("C:\\work", Windows)
  assert_true(write_permission_detail(windows).contains("Access is denied"))
  assert_true(write_directory_detail(windows).contains("Access is denied"))

  assert_eq(command_display(["echo", "hello"]), "`echo` `hello`")
  assert_true(
    interactive_host_detail(InvalidInput("Permission denied")).contains(
      "os error 13",
    ),
  )
  assert_true(
    interactive_host_detail(InvalidInput("No such file or directory")).contains(
      "os error 2",
    ),
  )
  assert_eq(interactive_host_detail(InvalidInput("detail")), "detail")
  assert_true(
    interactive_host_detail(CapabilityDenied(Process)).contains("Process"),
  )
  assert_true(
    interactive_host_detail(CapabilityUnavailable(Random)).contains("Random"),
  )
  assert_true(interactive_host_detail(NotFound(cwd)).contains("not found"))
  assert_true(
    interactive_host_detail(AlreadyExists(cwd)).contains("already exists"),
  )
  assert_eq(
    interactive_host_detail(RandomExhausted(requested=2, remaining=0)),
    "host randomness unavailable",
  )
  assert_eq(split_chooser_line(" a  b\tc\r"), ["a", "b", "c"])
  assert_eq(try! decode_chooser_selections(b"build one\nclean\n"), [
    ["build", "one"],
    ["clean"],
  ])
  try decode_chooser_selections(Bytes::from_array([0xff])[:]) catch {
    Query(message) => assert_true(message.contains("UTF-8"))
    error => fail("unexpected chooser error: \{Repr(error)}")
  } noraise {
    _ => fail("expected chooser UTF-8 error")
  }
}

///|
test "application whitebox behavior preserves process and evaluation exit contracts" {
  let span = @source.Span::origin(@source.SourceId::new(9960))
  let previous = @env.get_env_var("MOONJUST_OS")
  @env.set_env_var("MOONJUST_OS", "windows")
  defer (match previous {
    Some(value) => @env.set_env_var("MOONJUST_OS", value)
    None => @env.unset_env_var("MOONJUST_OS")
  })
  let errors : Array[ApplicationError] = [
    Evaluation(ProcessFailure(code=17, span~)),
    Evaluation(BacktickFailure(code=18, span~)),
    Evaluation(ProcessSignaled(signal=Terminate, span~)),
    InteractiveProcess(
      kind="command",
      command="tool",
      termination=Signaled(Hangup),
    ),
    InteractiveProcess(kind="chooser", command="fzf", termination=Exited(5)),
    InteractiveProcess(
      kind="chooser",
      command="fzf",
      termination=Signaled(Hangup),
    ),
    InteractiveProcess(
      kind="chooser",
      command="fzf",
      termination=Signaled(Interrupt),
    ),
    InteractiveProcess(
      kind="chooser",
      command="fzf",
      termination=Signaled(Terminate),
    ),
    InteractiveProcess(
      kind="chooser",
      command="fzf",
      termination=Signaled(OtherSignal(9)),
    ),
    InteractiveProcess(
      kind="chooser",
      command="fzf",
      termination=Interrupted(Hangup),
    ),
  ]
  for error in errors {
    assert_true(error.exit_code() > 0)
    assert_true(error.message().length() > 0)
  }
  assert_true(errors[3].message().contains("terminated by signal"))
  assert_true(errors[4].message().contains("exit code"))
  assert_true(stable_application_error_message(errors[0]).contains("MJ-EVAL"))
  assert_true(
    stable_application_error_message(
      Executor(Evaluation(UndefinedVariable(name="x", span~))),
    ).contains("MJ-EVAL"),
  )
}

///|
test "application whitebox behavior normalizes diagnostic source display paths" {
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  for
    row in [
      ("<stdin>", "justfile"),
      ("README.md", "justfile"),
      ("/workspace/sub/tasks.just", "sub/tasks.just"),
      ("relative.just", "relative.just"),
    ] {
    let (name, expected) = row
    let source = @source.Source::from_text(
      @source.SourceId::new(9961),
      name,
      "run:\n",
    )
    assert_eq(diagnostic_source(source, cwd).name(), expected)
  }
  assert_eq(diagnostic_load_cwd(try! @cli.parse_arguments([], {}), cwd), cwd)
  assert_eq(
    diagnostic_load_cwd(
      try! @cli.parse_arguments(["--justfile", "sub/tasks.just"], {}),
      cwd,
    ).as_string(),
    "/workspace/sub",
  )
  assert_eq(
    diagnostic_load_cwd(
      try! @cli.parse_arguments(["--justfile", "/config/tasks.just"], {}),
      cwd,
    ).as_string(),
    "/config",
  )
}

///|
test "application whitebox behavior exercises platform context and setting evaluation" {
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let project = application_behavior_project(
    "set shell := ['bash', '-eu']\n" +
    "set tempdir := '.tmp'\n" +
    "set dotenv-filename := ['.env']\n" +
    "set export\nroot:\n",
  )
  let parent = @evaluator.Environment::new()
  let arguments = try! @cli.parse_arguments(["--shell", "zsh", "--jobs", "4"], {})
  let selected = try! selected_shell(project.root(), parent, arguments, Unix)
  assert_eq(selected.program(), "zsh")
  let selected_windows = try! selected_shell(
    project.root(),
    parent,
    try! @cli.parse_arguments([], {}),
    Windows,
  )
  assert_true(selected_windows.program().length() > 0)
  assert_eq(
    try! evaluated_string_setting(project.root(), parent, "tempdir"),
    Some(".tmp"),
  )
  assert_eq(
    try! evaluated_const_string_setting(project.root(), parent, [], "tempdir"),
    Some(".tmp"),
  )
  assert_true(
    try! (evaluated_const_shell_setting(project.root(), parent, [], "shell")
    is Some(_)),
  )
  let directories = try! @workdir.WorkingDirectoryModel::from_stdin(cwd)
  let context = project_evaluation_context(
    project,
    @modulepath.ModulePath::root(),
    cwd,
    directories,
    arguments,
    cwd,
    environment=[
      ("HOME", "/home/test"),
      ("XDG_CONFIG_HOME", "/config"),
      ("XDG_DATA_HOME", "/data"),
      ("XDG_CACHE_HOME", "/cache"),
      ("XDG_RUNTIME_DIR", "/run/user"),
    ],
    platform=@host.PlatformInfo::new(
      Linux,
      "x86_64",
      Unix,
      executable="/usr/bin/just",
      pid=12,
      num_cpus=8,
    ),
  )
  assert_eq(
    context.home_directory(),
    Some(try! @path.PathValue::new("/home/test", Unix)),
  )
  assert_eq(
    context.config_directory(),
    Some(try! @path.PathValue::new("/config", Unix)),
  )
  assert_eq(
    context.data_directory(),
    Some(try! @path.PathValue::new("/data", Unix)),
  )
  assert_eq(
    context.cache_directory(),
    Some(try! @path.PathValue::new("/cache", Unix)),
  )
  assert_eq(
    context.runtime_directory(),
    Some(try! @path.PathValue::new("/run/user", Unix)),
  )
  assert_eq(context.pid(), Some(12))
  assert_eq(context.num_cpus(), Some(8))
  assert_eq(context.num_jobs(), Some(4))
  assert_eq(
    context.executable(),
    Some(try! @path.PathValue::new("/usr/bin/just", Unix)),
  )
}

///|
test "global context covers platform fallbacks and invalid requests" {
  let unix_cwd = try! @path.PathValue::new("/workspace/project", Unix)
  let global = try! @cli.parse_arguments(["--global-justfile"], {})

  let linux = @host.FakeHost::new(
    unix_cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  linux.set_env("HOME", "/home/test")
  let linux_file = try! @path.PathValue::new(
    "/home/test/.config/just/justfile",
    Unix,
  )
  linux.put_file(linux_file, b"root:\n")
  assert_eq(
    try! resolve_global_context(
      linux,
      linux,
      global,
      ApplicationContext::new(unix_cwd),
    ).global_justfile(),
    Some(linux_file),
  )

  let other = @host.FakeHost::new(
    unix_cwd,
    @host.PlatformInfo::new(Other("freebsd"), "x86_64", Unix),
  )
  other.set_env("HOME", "/home/other")
  let other_file = try! @path.PathValue::new(
    "/home/other/Library/Application Support/just/justfile",
    Unix,
  )
  other.put_file(other_file, b"root:\n")
  assert_eq(
    try! resolve_global_context(
      other,
      other,
      global,
      ApplicationContext::new(unix_cwd),
    ).global_justfile(),
    Some(other_file),
  )

  let windows_cwd = try! @path.PathValue::new("C:\\work", Windows)
  let windows = @host.FakeHost::new(
    windows_cwd,
    @host.PlatformInfo::new(Windows, "x86_64", Windows),
  )
  windows.set_env("APPDATA", "C:\\Users\\test\\AppData\\Roaming")
  let windows_file = try! @path.PathValue::new(
    "C:\\Users\\test\\AppData\\Roaming\\just\\justfile",
    Windows,
  )
  windows.put_file(windows_file, b"root:\n")
  assert_eq(
    try! resolve_global_context(
      windows,
      windows,
      global,
      ApplicationContext::new(windows_cwd),
    ).global_justfile(),
    Some(windows_file),
  )

  let missing = @host.FakeHost::new(
    unix_cwd,
    @host.PlatformInfo::new(Macos, "aarch64", Unix),
  )
  try
    resolve_global_context(
      missing,
      missing,
      global,
      ApplicationContext::new(unix_cwd),
    )
  catch {
    Query(message) => assert_true(message.contains("not found"))
    error => fail("unexpected missing global error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing global justfile")
  }

  for
    arguments in [
      try! @cli.parse_arguments(["--global-justfile", "--init"], {}),
      try! @cli.parse_arguments(["--global-justfile", "dir/recipe"], {}),
    ] {
    try
      resolve_global_context(
        linux,
        linux,
        arguments,
        ApplicationContext::new(unix_cwd),
      )
    catch {
      Query(_) => ()
      error => fail("unexpected invalid global request: \{Repr(error)}")
    } noraise {
      _ => fail("expected invalid global request")
    }
  }
}

///|
test "dotenv merge updates duplicates only when override is enabled" {
  assert_eq(
    merge_dotenv_entries([("A", "old")], [("A", "new"), ("B", "added")], true),
    [("A", "new"), ("B", "added")],
  )
  assert_eq(merge_dotenv_entries([("A", "old")], [("A", "new")], false), [
    ("A", "old"),
  ])
}
