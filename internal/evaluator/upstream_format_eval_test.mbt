///|
fn eval_upstream_format(text : String) -> String raise EvaluationError {
  let source = @source.Source::from_text(
    @source.SourceId::new(706),
    "expr",
    text,
  )
  evaluate_source(source).to_string()
}

///|
test "upstream format_string::delimiter_may_be_escaped_in_double_quoted_strings" {
  assert_eq(try! eval_upstream_format("f\"{{{{\""), "{{")
}

///|
test "upstream format_string::delimiter_may_be_escaped_in_single_quoted_strings" {
  assert_eq(try! eval_upstream_format("f'{{{{'"), "{{")
}

///|
test "upstream format_string::double_quotes_process_escapes" {
  assert_eq(
    try! eval_upstream_format("f\"\\u{61}{{\"b\"}}\\u{63}{{\"d\"}}\\u{65}\""),
    "abcde",
  )
}

///|
test "upstream format_string::escaped_delimiter_in_single_quoted_format_string" {
  assert_eq(try! eval_upstream_format("f'\\{{{{'"), "\\{{")
}

///|
test "upstream format_string::escaped_delimiter_is_ignored_in_normal_strings" {
  assert_eq(try! eval_upstream_format("'{{{{'"), "{{{{")
}

///|
test "upstream format_string::indented_format_strings" {
  assert_eq(
    try! eval_upstream_format("f'''\n  a\n  {{'b'}}\n  c\n'''"),
    "a\nb\nc\n",
  )
}

///|
test "upstream format_string::indented_format_strings_are_unindented_once" {
  assert_eq(try! eval_upstream_format("f'''\n\n  foo\n'''"), "\nfoo\n")
}

///|
test "upstream format_string::single_quotes_do_not_process_escapes" {
  assert_eq(
    try! eval_upstream_format("f'\\n{{'a'}}\\n{{'b'}}\\n'"),
    "\\na\\nb\\n",
  )
}

///|
test "upstream format_string::un_indented_format_strings" {
  assert_eq(
    try! eval_upstream_format("f'\n  a\n  {{'b'}}\n  c\n'"),
    "\n  a\n  b\n  c\n",
  )
}
