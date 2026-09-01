///|
fn eval_upstream_function(text : String) -> String raise EvaluationError {
  let source = @source.Source::from_text(
    @source.SourceId::new(702),
    "expr",
    text,
  )
  evaluate_source(source).display()
}

///|
test "upstream functions::capitalize" {
  assert_eq(try! eval_upstream_function("capitalize('BAR')"), "\"Bar\"")
}

///|
test "upstream functions::kebabcase" {
  assert_eq(try! eval_upstream_function("kebabcase('foo bar')"), "\"foo-bar\"")
}

///|
test "upstream functions::lowercamelcase" {
  assert_eq(
    try! eval_upstream_function("lowercamelcase('foo bar')"),
    "\"fooBar\"",
  )
}

///|
test "upstream functions::lowercase" {
  assert_eq(try! eval_upstream_function("lowercase('BAR')"), "\"bar\"")
}

///|
test "upstream functions::snakecase" {
  assert_eq(try! eval_upstream_function("snakecase('foo bar')"), "\"foo_bar\"")
}

///|
test "upstream functions::shoutykebabcase" {
  assert_eq(
    try! eval_upstream_function("shoutykebabcase('foo bar')"),
    "\"FOO-BAR\"",
  )
}

///|
test "upstream functions::shoutysnakecase" {
  assert_eq(
    try! eval_upstream_function("shoutysnakecase('foo bar')"),
    "\"FOO_BAR\"",
  )
}

///|
test "upstream functions::replace" {
  assert_eq(
    try! eval_upstream_function("replace('barbarbar', 'bar', 'foo')"),
    "\"foofoofoo\"",
  )
}

///|
test "upstream functions::replace_regex" {
  assert_eq(
    try! eval_upstream_function(
      "replace_regex('123bar123bar123bar', '\\d+bar', 'foo')",
    ),
    "\"foofoofoo\"",
  )
}

///|
test "upstream functions::clean" {
  assert_eq(try! eval_upstream_function("clean('a/../b')"), "\"b\"")
}

///|
test "upstream functions::semver_matches" {
  assert_eq(
    try! eval_upstream_function("semver_matches('0.1.0', '>=0.1.0')"),
    "\"true\"",
  )
}
