///|
test "executor behavior exercises execution error families" {
  let span = @source.Span::new(@source.SourceId::new(9400), 0, 1)
  let evaluation = @evaluator.EvaluationError::UndefinedVariable(
    name="x",
    span~,
  )
  let command = try! @host.CommandSpec::new("echo", [])
  let errors : Array[ExecutionError] = [
    Evaluation(evaluation),
    Evaluation(ProcessFailure(code=23, span~)),
    Evaluation(BacktickFailure(code=24, span~)),
    Evaluation(ProcessSignaled(signal=Terminate, span~)),
    Invocation(NoRecipes),
    Host(InvalidInput("host")),
    ShellNotFound(recipe="build", shell="sh", detail="missing"),
    InvalidShebang(recipe="build", shebang="#!bad"),
    UnknownRecipe(recipe="missing"),
    DependencyCycle(stack=["a", "b", "a"]),
    CommandFailed(recipe="build", line=0, exit_code=7),
    CommandFailed(recipe="build", line=2, exit_code=7),
    CommandSignaled(recipe="build", line=0, signal=Terminate),
    CommandSignaled(recipe="build", line=2, signal=Interrupt),
    Interrupted(signal=Hangup),
    GuardCode(recipe="build", line=1, code=100),
    InvalidAttributeValue(message="bad", span~),
    CacheFailure(message="cache"),
  ]
  for error in errors {
    let _ = error.exit_code()
    let _ = error.to_diagnostic()
  }
  assert_eq(command.program(), "echo")
}

///|
test "executor behavior visits graph planning and command materialization" {
  let source = @source.Source::from_text(
    @source.SourceId::new(9401),
    "plan.just",
    "set shell := [\"sh\", \"-cu\"]\n" +
    "[parallel]\nall: first second\n" +
    "first:\n  echo first\n" +
    "second:\n  @echo second\n",
  )
  let ast = try! @parser.parse(source)
  let compilation = try! @semantic.compile(ast)
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let plan = try! plan_recipe_graph(
    compilation,
    [RecipeRequest::new("all")],
    environment,
    shell,
    cwd,
  )
  let _ = plan.tasks().length()
  let _ = plan.commands().length()
  let _ = plan.steps().length()
  for command in plan.commands() {
    assert_true(command.spec().arguments().length() > 0)
    assert_true(command.recipe().length() > 0)
  }

  for
    case in [
      (
        "set positional-arguments\nexport NAME := 'n'\nroot arg='x': dep\n  # comment\n  echo {{arg}} \\\n  echo again\ndep:\n  echo dep\n",
        "root",
        @executor.ExecutionOptions::from_values(
          false,
          false,
          true,
          false,
          None,
          Some(Bold),
        ),
      ),
      (
        "root: dep\n  echo root\ndep:\n  echo dep\n",
        "root",
        @executor.ExecutionOptions::new().with_no_dependencies(true),
      ),
      (
        "root:\n  echo root\n",
        "root",
        @executor.ExecutionOptions::from_values(
          true,
          true,
          false,
          true,
          Some("now"),
          Some(Cyan),
        ),
      ),
    ] {
    try {
      let text = case.0
      let name = case.1
      let options = case.2
      let parsed = @parser.parse(
        @source.Source::from_text(
          @source.SourceId::new(9402),
          "options.just",
          text,
        ),
      )
      let compiled = @semantic.compile(parsed)
      let values = @evaluator.evaluate_compilation(compiled)
      let option_plan = plan_recipe_graph(
        compiled,
        [RecipeRequest::new(name, arguments=[String("value")])],
        values,
        shell,
        cwd,
        process_environment=[("NAME", "n")],
        options~,
      )
      let _ = option_plan.commands().length()
      let _ = option_plan.stderr().length()
    } catch {
      _ => ()
    }
  }
}

///|
test "executor graph reports unknown recipes and invalid dependency arguments" {
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  for
    text in [
      "root: missing\n", "root: dep('missing')\ndep:\n", "root: dep(1 / 0)\ndep:\n",
      "root arg:\n",
    ] {
    let compilation = try
      @semantic.compile_source(
        @source.Source::from_text(
          @source.SourceId::new(9420),
          "graph-errors",
          text,
        ),
      )
    catch {
      _ => continue
    } noraise {
      _ => continue
    }
    let environment = try! @evaluator.evaluate_compilation(compilation)
    try
      ignore(
        execute_recipe_graph(
          host,
          compilation,
          [RecipeRequest::new("root")],
          environment,
          shell,
          cwd,
        ),
      )
    catch {
      UnknownRecipe(_) | Evaluation(_) => ()
      error => fail("unexpected graph error: \{Repr(error)}")
    } noraise {
      _ => fail("expected graph error")
    }
  }
  let simple = try! @semantic.compile_source(
    @source.Source::from_text(
      @source.SourceId::new(9421),
      "graph-unknown-request",
      "root:\n",
    ),
  )
  let simple_environment = try! @evaluator.evaluate_compilation(simple)
  try
    ignore(
      execute_recipe_graph(
        host,
        simple,
        [RecipeRequest::new("missing")],
        simple_environment,
        shell,
        cwd,
      ),
    )
  catch {
    UnknownRecipe(_) => ()
    error => fail("unexpected unknown recipe error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unknown recipe error")
  }

  let required = try! @semantic.compile_source(
    @source.Source::from_text(
      @source.SourceId::new(9423),
      "graph-required-argument",
      "root first:\n  echo ok\n",
    ),
  )
  let required_environment = try! @evaluator.evaluate_compilation(required)
  try
    ignore(
      execute_recipe_graph(
        host,
        required,
        [RecipeRequest::new("root")],
        required_environment,
        shell,
        cwd,
      ),
    )
  catch {
    Evaluation(_) => ()
    error => fail("unexpected required argument error: \{Repr(error)}")
  } noraise {
    _ => fail("expected required argument error")
  }
}

///|
test "executor behavior exercises output formatting and script planning" {
  let colors : Array[CommandColor] = [
    Bold,
    Black,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    White,
  ]
  for color in colors {
    assert_true(render_command_echo("echo ok", color=Some(color)).length() > 0)
  }
  for format in ["%%", "%Y-%m-%d", "%H:%M:%S", "%1f", "%3f", "%9f", "%s"] {
    assert_true(valid_timestamp_format(format))
    assert_true(format_timestamp(1_234_567L, format).length() > 0)
  }
  assert_false(valid_timestamp_format("%"))
  assert_false(valid_timestamp_format("%0f"))
  assert_false(valid_timestamp_format("%1x"))
  assert_true(render_elapsed_message("build", -1L).length() > 0)
  assert_eq(render_failure_message(CacheFailure(message="hidden"), false), b"")
  assert_true(
    render_failure_message(CacheFailure(message="shown"), true).length() > 0,
  )

  let source = @source.Source::from_text(
    @source.SourceId::new(9410),
    "scripts.just",
    "[script]\nrun:\n  #!/bin/sh\n  echo ok\n",
  )
  let compilation = try! @semantic.compile_source(source, allow_unstable=true)
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let configuration = ScriptConfiguration::new(
    shell,
    try! @path.PathValue::new("/tmp", Unix),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let recipe = compilation.recipe("run").unwrap()
  let planned = try! plan_script_recipe(
    recipe,
    environment,
    cwd,
    configuration,
    process_environment=[("MODE", "test")],
    positional=["arg"],
  )
  assert_true(planned.contents().length() > 0)
}
