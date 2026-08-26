///|
fn perf_formatter_source(size : Int) -> @source.Source {
  let text = StringBuilder()
  for index in 0..<size {
    text.write_string("recipe")
    text.write_string(index.to_string())
    text.write_string(":\n  echo benchmark\n")
  }
  @source.Source::from_text(
    @source.SourceId::new(1573),
    "benchmark.just",
    text.to_string(),
  )
}

///|
fn bench_formatter_recipes(it : @bench.T, size : Int) -> Unit {
  let ast = try! @parser.parse(perf_formatter_source(size))
  it.bench(fn() { it.keep(format(ast)) })
}

///|
test "bench formatter recipes-10 preparsed" (it : @bench.T) {
  bench_formatter_recipes(it, 10)
}

///|
test "bench formatter recipes-100 preparsed" (it : @bench.T) {
  bench_formatter_recipes(it, 100)
}

///|
test "bench formatter recipes-1000 preparsed" (it : @bench.T) {
  bench_formatter_recipes(it, 1000)
}

///|
test "bench formatter recipes-5000 preparsed" (it : @bench.T) {
  bench_formatter_recipes(it, 5000)
}
