///|
fn perf_executor_source() -> @source.Source {
  let text = StringBuilder()
  text.write_string("root:")
  for index in 0..<999 {
    text.write_string(" node")
    text.write_string(index.to_string())
  }
  text.write_char('\n')
  for index in 0..<999 {
    text.write_string("node")
    text.write_string(index.to_string())
    text.write_string(":\n")
  }
  @source.Source::from_text(
    @source.SourceId::new(1575),
    "benchmark.just",
    text.to_string(),
  )
}

///|
test "bench executor plan dag-1000" (it : @bench.T) {
  let compilation = try! @semantic.compile(
    try! @parser.parse(perf_executor_source()),
  )
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let options = ExecutionOptions::new(dry_run=true)
  it.bench(fn() {
    it.keep(
      try! plan_recipe_graph(
        compilation,
        [RecipeRequest::new("root")],
        environment,
        shell,
        cwd,
        options~,
      ),
    )
  })
}

///|
test "bench executor plan dag-1000 retained tasks" (it : @bench.T) {
  let compilation = try! @semantic.compile(
    try! @parser.parse(perf_executor_source()),
  )
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let options = ExecutionOptions::new(dry_run=true).with_explain(true)
  it.bench(fn() {
    it.keep(
      try! plan_recipe_graph(
        compilation,
        [RecipeRequest::new("root")],
        environment,
        shell,
        cwd,
        options~,
      ),
    )
  })
}
