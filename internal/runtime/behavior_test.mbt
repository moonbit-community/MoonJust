///|
fn runtime_source(text : String) -> @semantic.Compilation {
  let source = @source.Source::from_text(
    @source.SourceId::new(710),
    "justfile",
    text,
  )
  try! @semantic.compile(try! @parser.parse(source))
}

///|
async test "runtime executes planned commands and returns child output" {
  let compilation = runtime_source("build:\n  echo build\n")
  let environment = @evaluator.Environment::new()
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let cwd = @path.PathValue::new("/workspace", Unix)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let plan = try! @planner.plan_recipe_graph(
    compilation,
    [@planner.RecipeRequest::new("build")],
    environment,
    shell,
    cwd,
  )
  host.expect_process(
    plan.commands()[0].spec(),
    @host.ProcessResult::new(0, b"ok\n", b""),
  )
  let report = try! execute_plan(host, host, host, plan)
  assert_eq(report.commands(), 1)
  assert_eq(report.stdout(), b"ok\n")
}
