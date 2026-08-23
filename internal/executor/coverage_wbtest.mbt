///|
fn executor_coverage_recipe(text : String) -> @syntax.Recipe {
  let source = @source.Source::from_text(
    @source.SourceId::new(9920),
    "executor.coverage",
    text,
  )
  let compilation = try! @semantic.compile_source(source, allow_unstable=true)
  compilation.recipe("run").unwrap()
}

///|
test "executor output formatting covers color and timestamp directives" {
  for color in [Bold, Black, Red, Green, Yellow, Blue, Magenta, Cyan, White] {
    assert_true(color_code(color).length() > 0)
    assert_true(paint_command("echo", Some(color)).contains("echo"))
  }
  assert_eq(paint_command("echo", None), "echo")
  for
    format in ["%%", "%Y-%m-%d", "%H:%M:%S", "%1f", "%3f", "%9f", "%s", "plain"] {
    assert_true(valid_timestamp_format(format))
    assert_true(format_timestamp(1_234_567L, format).length() > 0)
  }
  for invalid in ["%", "%0f", "%1x", "%q"] {
    assert_false(valid_timestamp_format(invalid))
  }
  assert_true(format_timestamp(-1L, "%s.%3f").length() > 0)
  assert_true(render_command_echo("echo ok").length() > 0)
  assert_true(
    render_command_echo("echo ok", timestamp=Some("12:00"), color=Some(Cyan)).length() >
    0,
  )
  assert_true(render_elapsed_message("build", -1L).length() > 0)
  assert_eq(render_failure_message(CacheFailure(message="x"), false), b"")
  assert_true(
    render_failure_message(CacheFailure(message="x"), true).length() > 0,
  )
}

///|
test "executor coverage closes formatting and script boundary branches" {
  assert_true(parse_shebang("#!/bin/sh ").unwrap().argument is None)
  let no_argument = parse_shebang("#!/bin/sh \t").unwrap()
  assert_eq(no_argument.interpreter, "/bin/sh")
  assert_true(no_argument.argument is None)
  assert_eq(format_timestamp(1_000L, "%"), "%")
  assert_eq(format_timestamp(1_000L, "%1"), "%1")
  assert_eq(format_timestamp(1_000L, "%q"), "%q")
  assert_true(format_timestamp(9_223_372_036_854_775_807L, "%s").length() > 0)

  let empty_source = @source.Source::from_text(
    @source.SourceId::new(9925),
    "executor.empty-script",
    "run:\n",
  )
  let empty_compilation = try! @semantic.compile_source(empty_source)
  let empty_recipe = empty_compilation.recipe("run").unwrap()
  assert_eq(positioned_script_lines(empty_recipe, [], false), [])
  assert_eq(script_bytes(empty_recipe, [], true, false, true), b"\xef\xbb\xbf")
  let windows = @host.PlatformInfo::new(Windows, "x86_64", Windows)
  assert_eq(
    execution_script_contents(b"echo ok\n", false, windows),
    b"echo ok\n",
  )

  let source = @source.Source::from_text(
    @source.SourceId::new(9926),
    "executor.script-boundaries",
    "run:\n  #!/bin/sh\n  echo ok\n",
  )
  let compilation = try! @semantic.compile_source(source)
  let recipe = compilation.recipe("run").unwrap()
  let lines = ["#!/bin/sh", "echo ok"]
  let positioned = positioned_script_lines(recipe, lines, true)
  assert_true(positioned.length() >= 2)
  assert_true(script_bytes(recipe, lines, false, true, true).length() > 0)
}

///|
test "executor script and line helpers preserve source alignment" {
  let recipe = executor_coverage_recipe(
    "[script]\nrun:\n  #!/bin/sh\n  echo ok\n",
  )
  assert_false(recipe_has_explicit_script_interpreter(recipe))
  assert_eq(parse_shebang("#!/bin/sh -eu").unwrap().interpreter, "/bin/sh")
  assert_eq(parse_shebang("#!/bin/sh -eu").unwrap().argument, Some("-eu"))
  assert_eq(parse_shebang("#!/bin/sh").unwrap().argument, None)
  assert_true(parse_shebang("# not a shebang") is None)
  assert_true(executable_name("C:\\bin\\pwsh.exe").contains("pwsh.exe"))
  assert_eq(inferred_extension("powershell.exe"), ".ps1")
  assert_eq(inferred_extension("sh"), "")
  assert_true(needs_bom("pwsh"))
  assert_false(needs_bom("sh"))
  let lines = ["#!/bin/sh", "echo ok"]
  assert_true(positioned_script_lines(recipe, lines, true).length() >= 2)
  assert_true(script_bytes(recipe, lines, true, true, false).length() > 0)
  let windows = @host.PlatformInfo::new(Windows, "x86_64", Windows)
  let stripped = execution_script_contents(
    @utf8.encode("\u{feff}#!/bin/sh\necho ok\n"),
    true,
    windows,
  )
  assert_eq(stripped, @utf8.encode("\u{feff}\necho ok\n"))
  assert_eq(source_line_sigils(recipe.lines()[0], true).0, 0)
}

///|
test "executor whitebox coverage visits planning helpers and environment exports" {
  let source = @source.Source::from_text(
    @source.SourceId::new(9921),
    "executor.helpers",
    "[continue('SIGINT', 'SIGQUIT')]\n" +
    "[positional-arguments]\n" +
    "run a *rest:\n" +
    "  echo first \\\n" +
    "  echo second\n",
  )
  let compilation = try! @semantic.compile_source(source, allow_unstable=true)
  let recipe = compilation.recipe("run").unwrap()
  let attributes = compilation.recipe_attributes("run")
  assert_eq(planned_continue_signals(None), [])
  assert_eq(planned_continue_signals(attributes), [Interrupt, OtherSignal(3)])
  let environment = @evaluator.Environment::new()
  environment.set("a", @value.String("one"))
  environment.set(
    "rest",
    @value.List([@value.String("two"), @value.String("three")]),
  )
  environment.mark_exported("a")
  environment.mark_exported("rest")
  assert_eq(positional_values(recipe, environment), ["one", "two", "three"])
  assert_eq(command_positional_values("run", ["one", "two"]), [
    "run", "one", "two",
  ])
  let exported = environment_with_exports(
    [("a", "old"), ("keep", "yes")],
    environment,
  )
  assert_true(exported.contains(("a", "one")))
  assert_true(exported.contains(("rest", "two three")))
  assert_true(exported.contains(("keep", "yes")))
  let parameter_exported = environment_with_parameter_exports(
    [],
    recipe,
    environment,
    true,
  )
  assert_true(parameter_exported.contains(("a", "one")))
  let (combined, end_index) = combined_recipe_line(recipe.lines(), 0)
  assert_true(combined.fragments().length() > 0)
  assert_true(end_index >= 0)
  assert_true(recipe_has_shebang(recipe) == false)
  let dependency = @syntax.Dependency::new(
    "run",
    recipe.span(),
    [String(@syntax.StringLiteral::new("'a'", "a", Raw, recipe.span()))],
    true,
    recipe.span(),
    starred_arguments=[0],
  )
  let expanded = expanded_dependency_argument_sets(dependency, [
    @value.List([@value.String("a"), @value.String("b")]),
  ])
  assert_eq(expanded.length(), 2)
  assert_eq(expanded[0], [@value.String("a")])
  let scalar_expanded = expanded_dependency_argument_sets(dependency, [
    @value.String("scalar"),
  ])
  assert_eq(scalar_expanded.length(), 1)
}

///|
test "executor whitebox coverage reports dependency evaluation errors" {
  let span = @source.Span::new(@source.SourceId::new(9927), 0, 1)
  let dependency = @syntax.Dependency::new(
    "run",
    span,
    [Variable(name="missing", span~)],
    false,
    span,
  )
  try
    ignore(dependency_arguments(dependency, @evaluator.Environment::new()))
  catch {
    Evaluation(_) => ()
    error => fail("unexpected dependency error: \{Repr(error)}")
  } noraise {
    _ => fail("expected dependency evaluation error")
  }
}

///|
test "executor whitebox coverage plans comments, continuations, and dry runs" {
  let recipe = executor_coverage_recipe(
    "run:\n  # comment\n  echo first \\\n  echo second\n  -echo ignored\n",
  )
  let environment = @evaluator.Environment::new()
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let commands : Array[PlannedCommand] = []
  let stderr : Array[Byte] = []
  plan_recipe_lines(
    recipe,
    environment,
    shell,
    cwd,
    [("A", "B")],
    ["arg"],
    ExecutionOptions::new(dry_run=true, verbose=true),
    false,
    commands,
    stderr,
    [],
  )
  assert_eq(commands.length(), 0)
  assert_true(stderr.length() > 0)
  let commands2 : Array[PlannedCommand] = []
  let stderr2 : Array[Byte] = []
  plan_recipe_lines(
    recipe,
    environment,
    shell,
    cwd,
    [],
    [],
    ExecutionOptions::new(),
    true,
    commands2,
    stderr2,
    [],
  )
  assert_true(commands2.length() >= 1)
  assert_true(stderr2.length() > 0)
}

///|
async test "executor whitebox coverage evaluates recipe shell, interpreter, cwd, env, and cache" {
  let source = @source.Source::from_text(
    @source.SourceId::new(9922),
    "executor.attributes",
    "[script('/bin/sh', '-eu'), working-directory('sub'), " +
    "env('MODE', 'test'), cache(inputs='input', outputs='output', extra='tag')]\n" +
    "run:\n  #!/bin/sh\n  echo ok\n",
  )
  let compilation = try! @semantic.compile_source(source, allow_unstable=true)
  let recipe = compilation.recipe("run").unwrap()
  let attributes = compilation.recipe_attributes("run")
  let shell_source = @source.Source::from_text(
    @source.SourceId::new(9923),
    "executor.shell",
    "[shell]\nrun:\n  echo ok\n",
  )
  let shell_compilation = try
    @semantic.compile_source(shell_source, allow_unstable=true)
  catch {
    error => fail("shell compilation failed: \{Repr(error)}")
  } noraise {
    value => value
  }
  let shell_attributes = shell_compilation.recipe_attributes("run")
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let shell = try! @environment.ShellConfiguration::new("fallback", ["-c"])
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let environment = @evaluator.Environment::new()
  let context = @evaluator.EvaluationContext::new(cwd~)
  let selected = try! recipe_shell(
    host, host, shell_attributes, environment, context, shell,
  )
  assert_eq(selected.program(), "fallback")
  let interpreter = try! recipe_script_interpreter(
    host, host, attributes, environment, context, shell, shell,
  )
  assert_eq(interpreter.program(), "/bin/sh")
  let selected_cwd = try! recipe_working_directory(
    host, host, attributes, environment, context, shell, cwd, cwd, cwd, recipe,
  )
  assert_eq(selected_cwd.as_string(), "/workspace/sub")
  let process_environment = try! recipe_process_environment(
    host,
    host,
    attributes,
    environment,
    context,
    shell,
    [("BASE", "yes")],
    recipe,
  )
  assert_true(process_environment.contains(("MODE", "test")))
  let configuration = ScriptConfiguration::new(
    shell,
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let script = PlannedScript::new(
    "run",
    b"\necho ok\n",
    Some("/bin/sh"),
    cwd,
    process_environment,
    configuration,
    [],
    false,
  )
  let cache = try! planned_cache_directive(
    host,
    host,
    attributes.unwrap(),
    environment,
    context,
    shell,
    [@value.String("arg")],
    script,
    "run",
  )
  assert_eq(cache.recipe(), "run")
  assert_eq(cache.extra(), "tag")
  assert_eq(cache.inputs(), ["input"])
  assert_eq(cache.outputs(), ["output"])
  assert_eq(empty_option_parameters(None), Set([]))
}

///|
fn executor_coverage_line_fixture(
  text : String,
) -> (@semantic.Compilation, @syntax.Recipe) raise {
  let compilation = @semantic.compile_source(
    @source.Source::from_text(
      @source.SourceId::new(9935),
      "executor-line-coverage.just",
      text,
    ),
  )
  (compilation, compilation.recipe("run").unwrap())
}

///|
fn executor_coverage_command(
  shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  command : String,
) -> @host.CommandSpec raise {
  let arguments = shell.arguments().to_owned()
  arguments.push(command)
  let spec = @host.CommandSpec::new(shell.program(), arguments)
  spec.set_cwd(cwd)
  spec.set_inherit_environment(false)
  spec.set_stdin(b"")
  spec.set_stdout(Capture)
  spec.set_stderr(Capture)
  spec
}

///|
test "executor line engines distinguish ignored child signals and interruption" {
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let environment = @evaluator.Environment::new()
  for effectful in [false, true] {
    for ignored in [false, true] {
      for interrupted in [false, true] {
        let prefix = if ignored { "-" } else { "" }
        let command = if interrupted { "interrupt" } else { "signal" }
        let (_, recipe) = executor_coverage_line_fixture(
          "run:\n  " + prefix + command + "\n",
        )
        let host = @host.FakeHost::new(
          cwd,
          @host.PlatformInfo::new(Linux, "x86_64", Unix),
        )
        let output = if interrupted {
          @host.ProcessResult::from_interruption(Interrupt, b"", b"")
        } else {
          @host.ProcessResult::from_signal(Terminate, b"", b"")
        }
        host.expect_process(
          executor_coverage_command(shell, cwd, command),
          output,
        )
        try {
          if effectful {
            ignore(
              execute_recipe_lines_effectful(
                host, recipe, environment, shell, cwd,
              ),
            )
          } else {
            ignore(execute_recipe_lines(host, recipe, environment, shell, cwd))
          }
        } catch {
          CommandSignaled(signal=Terminate, ..) if !ignored && !interrupted =>
            ()
          Interrupted(signal=Interrupt) if !ignored && interrupted => ()
          error => fail("unexpected line execution result: \{Repr(error)}")
        } noraise {
          _ if ignored => ()
          _ => fail("expected unignored process failure")
        }
        assert_eq(host.pending_process_expectations(), 0)
      }
    }
  }
}

///|
test "executor line engines map denied process capabilities" {
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let (_, recipe) = executor_coverage_line_fixture("run:\n  echo denied\n")
  for effectful in [false, true] {
    let host = @host.FakeHost::new(
      cwd,
      @host.PlatformInfo::new(Linux, "x86_64", Unix),
    )
    host.deny(Process)
    try {
      if effectful {
        ignore(
          execute_recipe_lines_effectful(
            host,
            recipe,
            @evaluator.Environment::new(),
            shell,
            cwd,
          ),
        )
      } else {
        ignore(
          execute_recipe_lines(
            host,
            recipe,
            @evaluator.Environment::new(),
            shell,
            cwd,
          ),
        )
      }
    } catch {
      Host(CapabilityDenied(Process)) => ()
      error => fail("unexpected process capability error: \{Repr(error)}")
    } noraise {
      _ => fail("expected denied process capability")
    }
  }
}

///|
test "executor whitebox coverage exercises option and plan value contracts" {
  let options = ExecutionOptions::new(
      dry_run=true,
      quiet=true,
      verbose=true,
      time=true,
      timestamp="%s",
      command_color=Red,
    )
    .with_jobs(4)
    .with_cache(false)
    .with_unstable(true)
    .with_no_dependencies(true)
    .with_explain(true)
    .with_color_enabled(true)
    .with_guards(true)
    .with_echo_quiet(true)
    .with_verbosity(3)
  assert_true(options.dry_run())
  assert_true(options.quiet())
  assert_true(options.echo_quiet())
  assert_true(options.verbose())
  assert_eq(options.verbosity(), 3)
  assert_true(options.time())
  assert_eq(options.timestamp(), Some("%s"))
  assert_eq(options.command_color(), Some(Red))
  assert_eq(options.jobs(), 4)
  assert_false(options.cache_enabled())
  assert_true(options.unstable())
  assert_true(options.no_dependencies())
  assert_true(options.explain())
  assert_true(options.color_enabled())
  assert_true(options.guards())
  assert_true(confirmation_answer_is_yes(" YES "))
  assert_true(confirmation_answer_is_yes("y"))
  assert_false(confirmation_answer_is_yes("no"))
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let configuration = ScriptConfiguration::new(
    shell,
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
    extension=".sh",
  )
  assert_eq(configuration.extension(), Some(".sh"))
  let report = ExecutionReport::new(b"out", b"err", 2)
  assert_eq(report.stdout(), b"out")
  assert_eq(report.stderr(), b"err")
  assert_eq(report.commands(), 2)
  let no_steps : Array[PlannedStep] = []
  let no_commands : Array[PlannedCommand] = []
  let first = ExecutionPlan::new(no_steps, no_commands, b"one", options)
  let second = ExecutionPlan::new(no_steps, no_commands, b"two", options)
  let plan = combine_execution_plans([first, second])
  assert_eq(plan.stderr(), b"onetwo")
  assert_eq(plan.with_stderr_prefix(b"prefix").stderr(), b"prefixonetwo")
  assert_eq(plan.confirmations().length(), 0)
  assert_true(combine_execution_plans([]).tasks().is_empty())

  let cycle_source = @source.Source::from_text(
    @source.SourceId::new(9940),
    "cycle.just",
    "run:\n",
  )
  let cycle_compilation = try! @semantic.compile_source(cycle_source)
  let cycle_key = execution_key("run", [])
  let cycle_host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  try
    run_graph_recipe(
      cycle_host,
      cycle_compilation,
      "run",
      [],
      @evaluator.Environment::new(),
      shell,
      cwd,
      [],
      ExecutionOptions::new(),
      Set([]),
      [cycle_key],
    )
  catch {
    DependencyCycle(stack=["run", "run"]) => ()
    error => fail("unexpected graph cycle error: \{Repr(error)}")
  } noraise {
    _ => fail("expected graph cycle")
  }
}

///|
test "executor whitebox coverage exercises planned value accessors" {
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let platform = @host.PlatformInfo::new(Linux, "x86_64", Unix)
  let configuration = ScriptConfiguration::new(
    shell,
    cwd,
    platform,
    extension=".sh",
  )
  assert_eq(configuration.interpreter(), shell)
  assert_eq(configuration.temporary_directory(), cwd)
  assert_eq(configuration.platform(), platform)
  let spec = try! @host.CommandSpec::new("sh", ["-cu", "echo ok"])
  let command = PlannedCommand::new(
    spec,
    "build",
    7,
    true,
    echo=b"echo ok\n",
    is_guard=true,
    continue_signals=[Interrupt],
  )
  assert_eq(command.spec(), spec)
  assert_eq(command.recipe(), "build")
  assert_eq(command.line(), 7)
  assert_true(command.ignore_error())
  assert_true(command.is_guard())
  assert_eq(command.echo(), b"echo ok\n")
  assert_eq(command.continue_signals(), [Interrupt])
  assert_true(Repr(command).to_string().contains("build"))

  let source = @source.Source::from_text(
    @source.SourceId::new(9924),
    "line.just",
    "build:\n  echo ok\n",
  )
  let compilation = try! @semantic.compile_source(source)
  let recipe = compilation.recipe("build").unwrap()
  let context = @evaluator.EvaluationContext::new(cwd~)
  let line = PlannedLine::new(
    recipe.lines()[0],
    @evaluator.Environment::new(),
    context,
    shell,
    cwd,
    [("MODE", "test")],
    ExecutionOptions::new(),
    "build",
    positional=["one"],
    false,
    2,
    continue_signals=[Hangup],
  )
  assert_eq(line.recipe(), "build")
  assert_eq(line.positional(), ["one"])
  assert_eq(line.line(), 2)
  assert_eq(line.continue_signals(), [Hangup])
  assert_true(Repr(line).to_string().contains("build"))

  let script = PlannedScript::new(
    "script",
    b"echo ok\n",
    Some("#!/bin/sh"),
    cwd,
    [("MODE", "test")],
    configuration,
    ["arg"],
    true,
    continue_signals=[Terminate],
  )
  assert_eq(script.recipe(), "script")
  assert_eq(script.contents(), b"echo ok\n")
  assert_eq(script.cwd(), cwd)
  assert_eq(script.environment(), [("MODE", "test")])
  assert_eq(script.configuration(), configuration)
  assert_eq(script.positional(), ["arg"])
  assert_true(script.quiet())
  assert_eq(script.continue_signals(), [Terminate])
  assert_true(Repr(script).to_string().contains("script"))

  let cache = CacheDirective::new(
    "script",
    "echo ok",
    "sh",
    ["-cu"],
    [("MODE", "test")],
    ".sh",
    cwd,
    ["arg"],
    "tag",
    ["input"],
    ["output"],
  )
  assert_eq(cache.recipe(), "script")
  assert_eq(cache.body(), "echo ok")
  assert_eq(cache.interpreter(), "sh")
  assert_eq(cache.interpreter_arguments(), ["-cu"])
  assert_eq(cache.environment(), [("MODE", "test")])
  assert_eq(cache.extension(), ".sh")
  assert_eq(cache.working_directory(), cwd)
  assert_eq(cache.positional(), ["arg"])
  assert_eq(cache.extra(), "tag")
  assert_eq(cache.inputs(), ["input"])
  assert_eq(cache.outputs(), ["output"])
  assert_true(Repr(cache).to_string().contains("script"))

  let task = ExecutionTask::new(
    3,
    4,
    "script",
    [Command(command, b"echo\n")],
    [1, 2],
    cache~,
    print_exit_message=false,
    preamble=b"start\n",
  )
  assert_eq(task.id(), 3)
  assert_eq(task.order(), 4)
  assert_eq(task.recipe(), "script")
  assert_eq(task.steps().length(), 1)
  assert_eq(task.dependencies(), [1, 2])
  assert_true(task.cache() is Some(_))
  assert_false(task.print_exit_message())
  assert_eq(task.preamble(), b"start\n")
  assert_true(Repr(task).to_string().contains("script"))
  let request = ConfirmationRequest::new("script", "Continue?", true)
  assert_eq(request.recipe(), "script")
  assert_eq(request.prompt(), "Continue?")
  assert_true(request.is_dependency())

  let first_task = ExecutionTask::new(
    0,
    0,
    "first",
    [Command(command, b"")],
    [],
    preamble=b"first\n",
  )
  let second_task = ExecutionTask::new(
    0,
    0,
    "second",
    [Command(command, b"")],
    [],
    preamble=b"second\n",
  )
  let first_plan = ExecutionPlan::new(
    [Command(command, b"")],
    [command],
    b"a",
    ExecutionOptions::new(),
    tasks=[first_task],
    cache_directory=cwd,
    confirmations=[request],
  )
  let second_plan = ExecutionPlan::new(
    [Command(command, b"")],
    [command],
    b"b",
    ExecutionOptions::new(),
    tasks=[second_task],
  )
  let combined = combine_execution_plans([first_plan, second_plan])
  assert_eq(combined.tasks().length(), 2)
  assert_eq(combined.tasks()[0].id(), 0)
  assert_eq(combined.tasks()[1].id(), 1)
  assert_eq(combined.tasks()[1].dependencies(), [0])
  assert_eq(combined.cache_directory(), Some(cwd))
  assert_eq(combined.confirmations().length(), 1)
  assert_true(Repr(combined).to_string().contains("task_count"))
  assert_true(
    Repr(ExecutionReport::new(b"out", b"err", 2))
    .to_string()
    .contains("stdout_bytes"),
  )
}

///|
async test "executor async planner preserves attributes dependencies and cache metadata" {
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let source = @source.Source::from_text(
    @source.SourceId::new(9930),
    "executor-async-coverage.just",
    "set lists\nset export\nset positional-arguments\nset ignore-comments\n" +
    "[parallel, doc('Run the build'), confirm('Proceed?'), no-quiet, exit-message, continue('SIGINT'), env('MODE', 'test'), working-directory('sub')]\n" +
    "run arg='default' +rest: (first 'one') (second 'two') && cleanup\n" +
    "  # ignored\n  echo {{arg}} \\\n  {{rest}}\n" +
    "first value:\n  echo {{value}}\n" +
    "second value:\n  echo {{value}}\n" +
    "cleanup:\n  echo cleanup\n",
  )
  let compilation = try! @semantic.compile_source(source, allow_unstable=true)
  let global = try! @evaluator.evaluate_compilation(compilation)
  let context = @evaluator.EvaluationContext::new(cwd~)
  let configuration = ScriptConfiguration::new(
    shell,
    try! @path.PathValue::new("/tmp", Unix),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
    extension=".sh",
  )
  let plan = try! plan_recipe_graph_async(
    host,
    host,
    compilation,
    [
      RecipeRequest::new("run", arguments=[
        String("chosen"),
        List([String("a"), String("b")]),
      ]),
    ],
    global,
    context,
    shell,
    cwd,
    configuration,
    process_environment=[("BASE", "yes")],
    options=ExecutionOptions::new()
      .with_jobs(3)
      .with_explain(true)
      .with_color_enabled(true)
      .with_verbosity(2),
  )
  assert_true(plan.tasks().length() >= 4)
  assert_eq(plan.confirmations().length(), 1)
  assert_eq(plan.confirmations()[0].prompt(), "Proceed?")
  assert_true(plan.tasks().any(fn(task) { task.preamble().length() > 0 }))
  assert_true(plan.tasks().any(fn(task) { task.dependencies().length() >= 2 }))

  let cached_source = @source.Source::from_text(
    @source.SourceId::new(9931),
    "executor-cache-coverage.just",
    "[script]\n[cache(inputs='input', outputs='output', extra='tag')]\n" +
    "cached:\n  echo cache\n",
  )
  let cached_compilation = try! @semantic.compile_source(
    cached_source,
    allow_unstable=true,
  )
  let cached_plan = try! plan_recipe_graph_async(
    host,
    host,
    cached_compilation,
    [RecipeRequest::new("cached")],
    try! @evaluator.evaluate_compilation(cached_compilation),
    context,
    shell,
    cwd,
    configuration,
    options=ExecutionOptions::new().with_unstable(true),
    cache_directory=try! @path.PathValue::new("/cache", Unix),
  )
  assert_eq(
    cached_plan.cache_directory(),
    Some(try! @path.PathValue::new("/cache", Unix)),
  )
  assert_eq(cached_plan.tasks().length(), 1)
  guard cached_plan.tasks()[0].cache() is Some(cache) else {
    fail("expected cache directive")
  }
  assert_eq(cache.inputs(), ["input"])
  assert_eq(cache.outputs(), ["output"])
  assert_eq(cache.extra(), "tag")
}
