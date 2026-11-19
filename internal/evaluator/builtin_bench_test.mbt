///|
test "evaluate a parsed expression containing 48 pure builtin calls" (
  b : @bench.T,
) {
  let term = "trim(uppercase(lowercase(' X ')))"
  let source = @source.Source::from_text(
    @source.SourceId::new(0),
    "builtin-bench",
    Array::make(16, term).join(" + "),
  )
  let expression = try! @parser.parse_expression(source)
  assert_eq(
    (try! @evaluator.evaluate(expression)).to_string(),
    "XXXXXXXXXXXXXXXX",
  )
  b.bench(fn() { b.keep(try! @evaluator.evaluate(expression)) })
}
