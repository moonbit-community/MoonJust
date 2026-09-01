///|
fn eval_upstream_logical(text : String) -> String raise EvaluationError {
  let source = @source.Source::from_text(
    @source.SourceId::new(703),
    "expr",
    text,
  )
  evaluate_source(source).to_string()
}

///|
test "upstream logical_operators::and_has_higher_precedence_than_or" {
  assert_eq(try! eval_upstream_logical("([] && 'foo') || 'bar'"), "bar")
  assert_eq(try! eval_upstream_logical("[] && 'foo' || 'bar'"), "bar")
  assert_eq(try! eval_upstream_logical("'a' && 'b' || 'c'"), "b")
}

///|
test "upstream logical_operators::and_has_lower_precedence_than_plus" {
  assert_eq(try! eval_upstream_logical("[] && 'goodbye' + 'foo'"), "")
  assert_eq(
    try! eval_upstream_logical("'foo' + 'hello' && 'goodbye'"),
    "goodbye",
  )
  assert_eq(try! eval_upstream_logical("'foo' + '' && 'goodbye'"), "goodbye")
  assert_eq(
    try! eval_upstream_logical("'foo' + 'hello' && 'goodbye' + 'bar'"),
    "goodbyebar",
  )
}

///|
test "upstream logical_operators::and_returns_empty_list_if_lhs_is_falsy" {
  assert_eq(try! eval_upstream_logical("[] && 'hello'"), "")
}

///|
test "upstream logical_operators::and_returns_rhs_if_lhs_is_truthy" {
  assert_eq(try! eval_upstream_logical("'hello' && 'goodbye'"), "goodbye")
}

///|
test "upstream logical_operators::empty_string_is_truthy" {
  assert_eq(try! eval_upstream_logical("'' || 'fallback'"), "")
  assert_eq(try! eval_upstream_logical("'' && 'rhs'"), "rhs")
}

///|
test "upstream logical_operators::nesting" {
  assert_eq(try! eval_upstream_logical("[] || [] || [] || [] || 'foo'"), "foo")
  assert_eq(
    try! eval_upstream_logical("'foo' && 'foo' && 'foo' && 'foo' && 'bar'"),
    "bar",
  )
}

///|
test "upstream logical_operators::or_has_lower_precedence_than_plus" {
  assert_eq(try! eval_upstream_logical("[] || 'goodbye' + 'foo'"), "goodbyefoo")
  assert_eq(
    try! eval_upstream_logical("'foo' + 'hello' || 'goodbye'"),
    "foohello",
  )
  assert_eq(try! eval_upstream_logical("'foo' + '' || 'goodbye'"), "foo")
  assert_eq(
    try! eval_upstream_logical("'foo' + 'hello' || 'goodbye' + 'bar'"),
    "foohello",
  )
}

///|
test "upstream logical_operators::or_returns_lhs_if_lhs_is_truthy" {
  assert_eq(try! eval_upstream_logical("'hello' || 'goodbye'"), "hello")
}

///|
test "upstream logical_operators::or_returns_rhs_if_lhs_is_falsy" {
  assert_eq(try! eval_upstream_logical("[] || 'hello'"), "hello")
}

///|
test "upstream negation::negates_empty_list" {
  let source = @source.Source::from_text(
    @source.SourceId::new(704),
    "expr",
    "![]",
  )
  assert_true(try! evaluate_source(source).truthy())
}

///|
test "upstream negation::negates_truthy_value" {
  let source = @source.Source::from_text(
    @source.SourceId::new(704),
    "expr",
    "!'foo'",
  )
  assert_true(!(try! evaluate_source(source).truthy()))
}

///|
test "upstream booleans::bool_true_values" {
  let values = ["bool(\"1\")", "bool(\"true\")"]
  for text in values {
    let source = @source.Source::from_text(
      @source.SourceId::new(705),
      "expr",
      text,
    )
    guard (try! evaluate_source(source).truthy()) else { fail(text) }
  }
}

///|
test "upstream slash_operator::no_lhs_once" {
  assert_eq(try! eval_upstream_logical("/ 'a'"), "/a")
}

///|
test "upstream slash_operator::no_lhs_twice" {
  assert_eq(try! eval_upstream_logical("/ 'a' / 'b'"), "/a/b")
  assert_eq(try! eval_upstream_logical("// 'a'"), "//a")
}

///|
test "upstream slash_operator::once" {
  assert_eq(try! eval_upstream_logical("'a' / 'b'"), "a/b")
}

///|
test "upstream slash_operator::twice" {
  assert_eq(try! eval_upstream_logical("'a' / 'b' / 'c'"), "a/b/c")
}
