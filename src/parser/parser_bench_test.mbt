///|
fn perf_parser_source(size : Int) -> @source.Source {
  let text = StringBuilder()
  for index in 0..<size {
    text.write_string("recipe")
    text.write_string(index.to_string())
    text.write_string(":\n  echo benchmark\n")
  }
  @source.Source::from_text(
    @source.SourceId::new(1571),
    "benchmark.just",
    text.to_string(),
  )
}

///|
fn bench_parser_recipes(it : @bench.T, size : Int) -> Unit {
  let input = perf_parser_source(size)
  let tokens = try! @lexer.lex(input)
  it.bench(fn() { it.keep(try! @parser.parse_tokens(input, tokens)) })
}

///|
test "bench parser recipes-10 prelexed" (it : @bench.T) {
  bench_parser_recipes(it, 10)
}

///|
test "bench parser recipes-100 prelexed" (it : @bench.T) {
  bench_parser_recipes(it, 100)
}

///|
test "bench parser recipes-1000 prelexed" (it : @bench.T) {
  bench_parser_recipes(it, 1000)
}

///|
test "bench parser recipes-5000 prelexed" (it : @bench.T) {
  bench_parser_recipes(it, 5000)
}
