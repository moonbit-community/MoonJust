///|
fn perf_semantic_source(size : Int) -> @source.Source {
  let text = StringBuilder()
  for index in 0..<size {
    text.write_string("recipe")
    text.write_string(index.to_string())
    text.write_string(":\n  echo benchmark\n")
  }
  @source.Source::from_text(
    @source.SourceId::new(1572),
    "benchmark.just",
    text.to_string(),
  )
}

///|
fn bench_semantic_recipes(it : @bench.T, size : Int) -> Unit {
  let ast = try! @parser.parse(perf_semantic_source(size))
  it.bench(fn() { it.keep(try! compile(ast)) })
}

///|
test "bench semantic compile recipes-10" (it : @bench.T) {
  bench_semantic_recipes(it, 10)
}

///|
test "bench semantic compile recipes-100" (it : @bench.T) {
  bench_semantic_recipes(it, 100)
}

///|
test "bench semantic compile recipes-1000" (it : @bench.T) {
  bench_semantic_recipes(it, 1000)
}

///|
test "bench semantic compile recipes-5000" (it : @bench.T) {
  bench_semantic_recipes(it, 5000)
}

///|
fn bench_project_validation(it : @bench.T, size : Int) -> Unit {
  let ast = try! @parser.parse(perf_semantic_source(size))
  let compilation = try! compile(ast, defer_recipe_linking=true)
  let project = ProjectCompilation::from_root(
    compilation,
    try! @path.PathValue::new("/workspace", Unix),
  )
  it.bench(fn() {
    try! validate_project_compilation(project)
    it.keep(project)
  })
}

///|
test "bench project validation recipes-10" (it : @bench.T) {
  bench_project_validation(it, 10)
}

///|
test "bench project validation recipes-100" (it : @bench.T) {
  bench_project_validation(it, 100)
}

///|
test "bench project validation recipes-1000" (it : @bench.T) {
  bench_project_validation(it, 1000)
}

///|
test "bench project validation recipes-5000" (it : @bench.T) {
  bench_project_validation(it, 5000)
}
