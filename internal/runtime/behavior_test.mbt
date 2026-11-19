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
    @host.PlatformInfo::new(Linux, Some("test"), Unix),
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
  let report = try! @runtime.execute_plan(host, host, host, plan)
  assert_eq(report.commands(), 1)
  assert_eq(report.stdout(), b"ok\n")
}

///|
priv struct AdvancingClockProcess(@host_testkit.FakeHost)

///|
impl @host.HostProcess for AdvancingClockProcess with fn run_process(self, _) -> @host.ProcessResult raise @host.HostError {
  self.0.set_clock_millis(2000L)
  @host.ProcessResult::new(0, b"", b"")
}

///|
async test "command timestamps read the clock after the previous command completes" {
  let cwd = @path.PathValue::new("/workspace", Unix)
  let platform = @host.PlatformInfo::new(Linux, None, Unix)
  let host = @host_testkit.FakeHost::new(cwd, platform)
  let process = AdvancingClockProcess(host)
  let shell = @environment.ShellConfiguration::new("sh", ["-cu"])
  let plan = @planner.plan_recipe_graph_async(
    process,
    host,
    runtime_source("run:\n  echo one\n  echo two\n"),
    [@planner.RecipeRequest::new("run")],
    @evaluator.Environment::new(),
    @evaluator.EvaluationContext::new(cwd~),
    shell,
    cwd,
    @planner.ScriptConfiguration::new(shell, cwd, platform),
    options=@planner.ExecutionOptions::new(timestamp="%s"),
  )
  host.set_clock_millis(1000L)
  let report = @runtime.execute_plan(process, host, host, plan)
  assert_eq(report.stderr(), b"[1] echo one\n[2] echo two\n")
}
