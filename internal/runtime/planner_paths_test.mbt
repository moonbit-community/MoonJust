///|
async test "both planners preserve shell argv, dependency order, output and dry-run effects" {
  let compilation = runtime_source(
    "prepare:\n  echo prepare\nrun name: prepare\n  echo '{{name}}'\n",
  )
  let roots = [
    @planner.RecipeRequest::new("run", arguments=[String("two words")]),
  ]
  let shell = @environment.ShellConfiguration::new("sh", ["-cu"])
  for dry_run in [true, false] {
    let options = @planner.ExecutionOptions::new(dry_run~)
    for synchronous in [true, false] {
      let host = runtime_host()
      let cwd = host.current_dir()
      let argv : Array[Array[String]] = []
      let process = TestProcess(spec => {
        argv.push([spec.program()] + spec.arguments().to_owned())
        @host.ProcessResult::new(0, b"done\n", b"")
      })
      let global = @evaluator.Environment::new()
      let plan = if synchronous {
        @planner.plan_recipe_graph(
          compilation,
          roots,
          global,
          shell,
          cwd,
          options~,
        )
      } else {
        @planner.plan_recipe_graph_async(
          process,
          host,
          compilation,
          roots,
          global,
          @evaluator.EvaluationContext::new(cwd~),
          shell,
          cwd,
          @planner.ScriptConfiguration::new(shell, cwd, host.platform_info()),
          options~,
        )
      }
      ignore(
        @runtime.execute_plan_live(process, host, host, host, plan, (_, _) => ()),
      )
      let stdout = Buffer()
      let stderr = Buffer()
      for event in host.output_events() {
        match event.0 {
          Stdout => stdout.write_bytes(event.1)
          Stderr => stderr.write_bytes(event.1)
        }
      }
      assert_eq(stderr.to_bytes(), b"echo prepare\necho 'two words'\n")
      if dry_run {
        assert_true(argv.is_empty())
        assert_eq(stdout.to_bytes(), b"")
      } else {
        assert_eq(argv, [
          ["sh", "-cu", "echo prepare"],
          ["sh", "-cu", "echo 'two words'"],
        ])
        assert_eq(stdout.to_bytes(), b"done\ndone\n")
      }
    }
  }
}
