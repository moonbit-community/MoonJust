///|
fn format_upstream_remaining(text : String) -> String raise {
  format_source(
    @source.Source::from_text(@source.SourceId::new(899), "justfile", text),
  )
}

///|
test "upstream format::crlf_blank_lines_between_recipes_are_preserved" {
  assert_eq(
    try! format_upstream_remaining("a:\r\n echo a\r\n\r\nb:\r\n echo b\r\n"),
    "a:\n    echo a\n\nb:\n    echo b\n",
  )
}

///|
test "upstream justfile::tests::parse_export" {
  assert_eq(
    try! format_upstream_remaining("export a := 'hello'\n"),
    "export a := 'hello'\n",
  )
}

///|
test "upstream justfile::tests::string_escapes" {
  assert_eq(
    try! format_upstream_remaining("a := \"\\n\\t\\r\\\"\\\\\"\n"),
    "a := \"\\n\\t\\r\\\"\\\\\"\n",
  )
}

///|
test "upstream justfile::tests::string_quote_escape" {
  assert_eq(
    try! format_upstream_remaining("a := \"hello\\\"\"\n"),
    "a := \"hello\\\"\"\n",
  )
}

///|
test "upstream justfile::tests::env_functions" {
  assert_eq(
    try! format_upstream_remaining(
      "x := env_var('foo',)\n\na:\n  {{env_var_or_default('foo' + 'bar', 'baz',)}} {{ env_var(env_var('baz')) }}",
    ),
    "x := env_var('foo')\n\na:\n    {{ env_var_or_default('foo' + 'bar', 'baz') }} {{ env_var(env_var('baz')) }}\n",
  )
}
