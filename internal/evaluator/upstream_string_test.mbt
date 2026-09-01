///|
fn eval_upstream_string(text : String) -> String raise EvaluationError {
  let source = @source.Source::from_text(
    @source.SourceId::new(707),
    "expr",
    text,
  )
  evaluate_source(source).to_string()
}

///|
test "upstream string::raw_string" {
  assert_eq(try! eval_upstream_string("'foo'"), "foo")
}

///|
test "upstream string::multiline_raw_string" {
  assert_eq(try! eval_upstream_string("'''foo\nbar'''"), "foo\nbar")
}

///|
test "upstream string::multiline_cooked_string" {
  assert_eq(try! eval_upstream_string("\"\"\"foo\\nbar\"\"\""), "foo\nbar")
}

///|
test "upstream string::unicode_escapes_with_all_hex_digits" {
  assert_eq(try! eval_upstream_string("\"\\u{1F600}\""), "😀")
}

///|
test "upstream string::valid_unicode_escape" {
  assert_eq(try! eval_upstream_string("\"\\u{61}\""), "a")
}

///|
test "upstream string::maximum_valid_unicode_escape" {
  assert_eq(try! eval_upstream_string("\"\\u{10FFFF}\""), "\u{10FFFF}")
}
