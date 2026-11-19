///|
async test "worker pool and shutdown permits are bounded by the three-task graph" {
  let source = @source.Source::from_text(
    @source.SourceId::new(1),
    "justfile",
    "[parallel]\nrun: left right\nleft:\nright:\n",
  )
  let compilation = @semantic.compile(@parser.parse(source))
  let cwd = @path.PathValue::new("/workspace", Unix)
  let platform = @host.PlatformInfo::new(Linux, None, Unix)
  let host = @host_testkit.FakeHost::new(cwd, platform)
  let shell = @environment.ShellConfiguration::new("sh", ["-cu"])
  for (jobs, workers) in [(1, 1), (2, 2), (2_147_483_647, 3)] {
    let plan = @planner.plan_recipe_graph_async(
      host,
      host,
      compilation,
      [@planner.RecipeRequest::new("run")],
      @evaluator.Environment::new(),
      @evaluator.EvaluationContext::new(cwd~),
      shell,
      cwd,
      @planner.ScriptConfiguration::new(shell, cwd, platform),
      options=@planner.ExecutionOptions::new().with_jobs(jobs),
    )
    assert_eq(plan.tasks().length(), 3)
    let coordinator = execution_coordinator(plan.tasks(), plan.options().jobs()).unwrap()
    assert_eq(coordinator.workers, workers)
    for id in 0..<3 {
      assert_eq(coordinator.next(), Some((id, false)))
      coordinator.finish(id, false)
    }
    for _ in 0..<workers {
      assert_true(coordinator.wake.try_acquire())
    }
    assert_false(coordinator.wake.try_acquire())
    // Exercise the same graph with actual workers, including the largest jobs value.
    let summary = execute_plan_live(host, host, host, host, plan, (_, _) => ())
    assert_eq(summary.commands(), 0)
  }
}
