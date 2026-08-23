///|
fn perf_evaluator_source() -> @source.Source {
  let text = StringBuilder()
  text.write_string("value0 := \"x\"\n")
  for index in 1..<1000 {
    text.write_string("value")
    text.write_string(index.to_string())
    text.write_string(" := value")
    text.write_string((index - 1).to_string())
    text.write_string(" + \"x\"\n")
  }
  @source.Source::from_text(
    @source.SourceId::new(1574),
    "benchmark.just",
    text.to_string(),
  )
}

///|
test "bench evaluator variables-1000 precompiled" (it : @bench.T) {
  let compilation = try! @semantic.compile(
    try! @parser.parse(perf_evaluator_source()),
  )
  it.bench(fn() { it.keep(try! evaluate_compilation(compilation)) })
}
