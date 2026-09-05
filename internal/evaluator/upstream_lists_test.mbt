///|
fn eval_upstream_list(text : String) -> String raise EvaluationError {
  let source = @source.Source::from_text(
    @source.SourceId::new(701),
    "expr",
    text,
  )
  evaluate_source(source).display()
}

///|
fn eval_upstream_list_context(text : String) -> String raise EvaluationError {
  let source = @source.Source::from_text(
    @source.SourceId::new(717),
    "expr",
    text,
  )
  let expression = @parser.parse_expression(source) catch {
    error => raise Parse(error)
  }
  let context = EvaluationContext::new(
    cwd=try! @path.PathValue::new("/tmp", Unix),
    lists=true,
    environment=[],
  )
  evaluate_with_context(expression, context).display()
}

///|
test "upstream lists::append_appends_to_each_element_of_a_list" {
  assert_eq(
    try! eval_upstream_list("append('.c', ['bar', 'baz bob'])"),
    "[\"bar.c\", \"baz bob.c\"]",
  )
}

///|
test "upstream lists::concatenation_broadcasts_string_over_list" {
  assert_eq(
    try! eval_upstream_list("'foo' + ['bar', 'baz']"),
    "[\"foobar\", \"foobaz\"]",
  )
}

///|
test "upstream lists::concatenation_combines_equal_length_lists_pairwise" {
  assert_eq(
    try! eval_upstream_list("['a', 'b'] + ['c', 'd']"),
    "[\"ac\", \"bd\"]",
  )
}

///|
test "upstream lists::concatenation_of_empty_lists_is_empty" {
  assert_eq(try! eval_upstream_list("[] + []"), "[]")
}

///|
test "upstream lists::concatenation_of_strings_is_a_string" {
  assert_eq(try! eval_upstream_list("'foo' + 'bar'"), "\"foobar\"")
}

///|
test "upstream lists::join_broadcasts_string_over_list" {
  assert_eq(
    try! eval_upstream_list("'foo' / ['bar', 'baz']"),
    "[\"foo/bar\", \"foo/baz\"]",
  )
}

///|
test "upstream lists::join_combines_equal_length_lists_pairwise" {
  assert_eq(
    try! eval_upstream_list("['a', 'b'] / ['c', 'd']"),
    "[\"a/c\", \"b/d\"]",
  )
}

///|
test "upstream lists::join_list_joins_lists_with_spaces" {
  assert_eq(try! eval_upstream_list("join_list(['bar', 'baz'])"), "\"bar baz\"")
}

///|
test "upstream lists::join_list_joins_with_separator" {
  assert_eq(
    try! eval_upstream_list("join_list(['bar', 'baz'], ', ')"),
    "\"bar, baz\"",
  )
}

///|
test "upstream lists::list_concatenation_appends_lists" {
  assert_eq(
    try! eval_upstream_list("['foo', 'bar'] ++ ['baz']"),
    "[\"foo\", \"bar\", \"baz\"]",
  )
}

///|
test "upstream lists::prepend_prepends_to_each_element_of_a_list" {
  assert_eq(
    try! eval_upstream_list("prepend('src/', ['bar', 'baz bob'])"),
    "[\"src/bar\", \"src/baz bob\"]",
  )
}

///|
test "upstream lists::quote_quotes_single_element_values_whole" {
  assert_eq(try! eval_upstream_list("quote('baz bob')"), "\"'baz bob'\"")
}

///|
test "upstream lists::split_keeps_empty_elements_with_explicit_separator" {
  assert_eq(
    try! eval_upstream_list("split('foo,,bar,', ',')"),
    "[\"foo\", \"\", \"bar\", \"\"]",
  )
}

///|
test "upstream lists::split_of_string_not_containing_separator_is_single_element" {
  assert_eq(try! eval_upstream_list("split('foo', ',')"), "\"foo\"")
}

///|
test "upstream lists::split_on_empty_separator_splits_into_characters" {
  assert_eq(
    try! eval_upstream_list("split('abc', '')"),
    "[\"a\", \"b\", \"c\"]",
  )
}

///|
test "upstream lists::split_splits_string_on_separator" {
  assert_eq(
    try! eval_upstream_list("split('foo,bar,baz', ',')"),
    "[\"foo\", \"bar\", \"baz\"]",
  )
}

///|
test "upstream lists::unary_join_broadcasts_over_list" {
  assert_eq(try! eval_upstream_list("/ ['foo', 'bar']"), "[\"/foo\", \"/bar\"]")
}

///|
test "upstream lists::len" {
  assert_eq(try! eval_upstream_list("len([])"), "\"0\"")
  assert_eq(try! eval_upstream_list("len('foo')"), "\"1\"")
  assert_eq(try! eval_upstream_list("len(['foo', 'bar'])"), "\"2\"")
}

///|
test "upstream lists::fstring_interpolations_space_join_lists" {
  assert_eq(try! eval_upstream_list("f\"{{['bar', 'baz']}}\""), "\"bar baz\"")
}

///|
test "upstream lists::absolute_path_of_empty_list_is_empty" {
  assert_eq(try! eval_upstream_list_context("absolute_path([])"), "[]")
}

///|
test "upstream lists::append_does_not_split_single_strings_with_lists_setting" {
  assert_eq(
    try! eval_upstream_list_context("append('.c', 'foo bar')"),
    "\"foo bar.c\"",
  )
}

///|
test "upstream lists::quote_of_empty_list_is_empty" {
  assert_eq(try! eval_upstream_list_context("quote([])"), "[]")
}

///|
test "upstream lists::quote_quotes_each_element_of_a_list" {
  assert_eq(
    try! eval_upstream_list_context("quote(['bar', 'baz bob'])"),
    "[\"'bar'\", \"'baz bob'\"]",
  )
}

///|
test "upstream lists::split_without_separator_of_whitespace_is_empty" {
  assert_eq(try! eval_upstream_list_context("split('  \t ')"), "[]")
}

///|
test "upstream lists::split_without_separator_splits_on_whitespace" {
  assert_eq(
    try! eval_upstream_list_context("split('  foo \t bar  baz ')"),
    "[\"foo\", \"bar\", \"baz\"]",
  )
}

///|
test "upstream lists::env_returns_default_when_no_variable_present" {
  assert_eq(
    try! eval_upstream_list_context("env(['ZADDY', 'XYZ'], 'baz')"),
    "\"baz\"",
  )
}

///|
test "upstream lists::env_returns_list_default" {
  assert_eq(
    try! eval_upstream_list_context("env(['ZADDY'], ['a', 'b'])"),
    "[\"a\", \"b\"]",
  )
}

///|
test "upstream lists::env_var_or_default_accepts_list_of_keys" {
  assert_eq(
    try! eval_upstream_list_context("env_var_or_default(['ZADDY', 'XYZ'], [])"),
    "[]",
  )
}

///|
test "upstream lists::env_with_empty_key_list_uses_default" {
  assert_eq(try! eval_upstream_list_context("env([], 'baz')"), "\"baz\"")
}

///|
test "upstream booleans::bool_false_values" {
  assert_eq(try! eval_upstream_list_context("bool([])"), "[]")
  assert_eq(try! eval_upstream_list_context("bool(\"\")"), "[]")
  assert_eq(try! eval_upstream_list_context("bool(\"0\")"), "[]")
  assert_eq(try! eval_upstream_list_context("bool(\"false\")"), "[]")
}
