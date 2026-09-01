///|
test "upstream assertions::assert_empty_string_without_lists" {
  assert_eq(try! eval_upstream_list("assert('a' == 'a', 'fail')"), "\"\"")
}

///|
test "upstream assertions::assert_message_may_be_omitted" {
  assert_eq(try! eval_upstream_list("assert('a' == 'a')"), "\"\"")
}

///|
test "upstream assertions::assert_evaluates_to_condition_with_lists" {
  assert_eq(
    try! eval_upstream_list_context("assert(['foo', 'bar'], 'fail')"),
    "[\"foo\", \"bar\"]",
  )
}

///|
test "upstream assertions::assert_without_message_evaluates_to_condition_with_lists" {
  assert_eq(
    try! eval_upstream_list_context("assert(['foo', 'bar'])"),
    "[\"foo\", \"bar\"]",
  )
}
