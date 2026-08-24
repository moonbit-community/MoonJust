///|
fn perf_formatter_source() -> @source.Source {
  let text = StringBuilder()
  for index in 0..<1000 {
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
test "bench formatter recipes-1000 preparsed" (it : @bench.T) {
  let ast = try! @parser.parse(perf_formatter_source())
  it.bench(fn() { it.keep(format(ast)) })
}
