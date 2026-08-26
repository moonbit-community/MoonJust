///|
fn perf_lexer_source(size : Int) -> @source.Source {
  let text = StringBuilder()
  for index in 0..<size {
    text.write_string("recipe")
    text.write_string(index.to_string())
    text.write_string(":\n  echo benchmark\n")
  }
  @source.Source::from_text(
    @source.SourceId::new(1570),
    "benchmark.just",
    text.to_string(),
  )
}

///|
fn bench_lexer_recipes(it : @bench.T, size : Int) -> Unit {
  let input = perf_lexer_source(size)
  it.bench(fn() { it.keep(try! @lexer.lex(input)) })
}

///|
test "bench lexer recipes-10" (it : @bench.T) {
  bench_lexer_recipes(it, 10)
}

///|
test "bench lexer recipes-100" (it : @bench.T) {
  bench_lexer_recipes(it, 100)
}

///|
test "bench lexer recipes-1000" (it : @bench.T) {
  bench_lexer_recipes(it, 1000)
}

///|
test "bench lexer recipes-5000" (it : @bench.T) {
  bench_lexer_recipes(it, 5000)
}
