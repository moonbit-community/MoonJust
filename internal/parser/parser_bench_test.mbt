///|
fn perf_parser_source() -> @source.Source {
  let text = StringBuilder()
  for index in 0..<1000 {
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
test "bench parser recipes-1000 prelexed" (it : @bench.T) {
  let input = perf_parser_source()
  let tokens = try! @lexer.lex(input)
  it.bench(fn() { it.keep(try! @parser.parse_tokens(input, tokens)) })
}
