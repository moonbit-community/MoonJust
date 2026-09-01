///|
fn eval_upstream_literal(text : String) -> String raise EvaluationError {
  let source = @source.Source::from_text(
    @source.SourceId::new(708),
    "expr",
    text,
  )
  evaluate_source(source).display()
}

///|
test "upstream list_literals::list_literals_are_lists" {
  assert_eq(try! eval_upstream_literal("[\"a\", \"b\"]"), "[\"a\", \"b\"]")
}

///|
test "upstream list_literals::list_literals_flatten_elements" {
  assert_eq(
    try! eval_upstream_literal("[\"pre\", [\"x\", \"y\"], \"post\"]"),
    "[\"pre\", \"x\", \"y\", \"post\"]",
  )
}

///|
test "upstream list_literals::list_literals_may_have_trailing_comma" {
  assert_eq(try! eval_upstream_literal("[\"a\", \"b\",]"), "[\"a\", \"b\"]")
}
