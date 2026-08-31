///|
test "upstream recursion_limit::bugfix" {
  let mut source_text = "foo: (x "
  for _ in 0..<500 {
    source_text += "("
  }
  let source = @source.Source::from_text(
    @source.SourceId::new(961),
    "justfile",
    source_text,
  )
  try ignore(@parser.parse(source)) catch {
    @parser.RecursionLimitExceeded(limit~, ..) => assert_true(limit > 0)
    error => fail("unexpected parser error: \{Repr(error)}")
  } noraise {
    _ => fail("expected parsing recursion depth exceeded")
  }
}
