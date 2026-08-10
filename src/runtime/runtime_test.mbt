///|
fn runtime_path(text : String) -> @path.PathValue {
  try! @path.PathValue::new(text, Unix)
}

///|
fn runtime_compilation(text : String) -> @semantic.Compilation {
  let source = @source.Source::from_text(
    @source.SourceId::new(88),
    "justfile",
    text,
  )
  try! @semantic.compile(try! @parser.parse(source))
}

///|
async test "runtime executes steps in order and retains failure output" {
  let compilation = runtime_compilation("build:\n  first\n  second\n")
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let plan = try! @executor.plan_recipe_graph(
    compilation,
    [@executor.RecipeRequest::new("build")],
    environment,
    shell,
    runtime_path("/workspace"),
  )
  for index, command in plan.commands() {
    host.expect_process(
      command.spec(),
      if index == 0 {
        @host.ProcessResult::new(0, b"first\n", b"")
      } else {
        @host.ProcessResult::new(7, b"", b"failed\n")
      },
    )
  }
  try execute_plan(host, host, host, plan) catch {
    Execution(
      error=CommandFailed(exit_code=7, ..),
      stdout~,
      stderr~,
      commands=2
    ) => {
      assert_eq(stdout, b"first\n")
      assert_eq(stderr, b"first\nsecond\nfailed\n")
    }
    error => fail("unexpected runtime error: \{Repr(error)}")
  } noraise {
    _ => fail("expected runtime failure")
  }
}

///|
async test "runtime cleans a materialized script after success" {
  let compilation = runtime_compilation(
    "[script]\nbuild:\n  #!/bin/sh\n  echo ok\n",
  )
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-eu"])
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let plan = try! @executor.plan_recipe_graph_async(
    host,
    host,
    compilation,
    [@executor.RecipeRequest::new("build")],
    environment,
    @evaluator.EvaluationContext::new(cwd=runtime_path("/workspace")),
    shell,
    runtime_path("/workspace"),
    @executor.ScriptConfiguration::new(
      shell,
      runtime_path("/tmp"),
      @host.PlatformInfo::new(Linux, "test", Unix),
    ),
  )
  let script = match plan.steps()[0] {
    Script(value, _) => value
    _ => abort("expected script step")
  }
  let builder = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let expected = try! @executor.materialize_script(builder, script)
  host.expect_process(
    expected.spec(),
    @host.ProcessResult::new(0, b"ok\n", b""),
  )
  let report = try! execute_plan(host, host, host, plan)
  assert_eq(report.stdout(), b"ok\n")
  assert_eq(host.pending_process_expectations(), 0)
}
