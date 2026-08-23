///|
fn perf_lexer_source() -> @source.Source {
  let text = StringBuilder()
  for index in 0..<1000 {
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
test "bench lexer recipes-1000" (it : @bench.T) {
  let input = perf_lexer_source()
  it.bench(fn() { it.keep(try! @lexer.lex(input)) })
}
