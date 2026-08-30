///|
fn formatted_source(text : String) -> String raise {
  @formatter.format_source(
    @source.Source::from_text(@source.SourceId::new(805), "justfile", text),
  )
}

///|
test "formatter preserves comments in an empty source" {
  assert_eq(formatted_source("\n\n# hello\n\n"), "\n# hello\n\n")
}

///|
test "formatter preserves adjacent recipes" {
  assert_eq(formatted_source("a:\nb:\n"), "a:\nb:\n")
}

///|
test "formatter keeps variadic parameters" {
  assert_eq(formatted_source("foo +a:\n"), "foo +a:\n")
}

///|
test "formatter keeps variadic string defaults" {
  assert_eq(formatted_source("foo +a='Hello':\n"), "foo +a='Hello':\n")
}

///|
test "formatter keeps raw string defaults" {
  assert_eq(formatted_source("foo a='b\\t':\n"), "foo a='b\\t':\n")
}

///|
test "formatter keeps exported assignments" {
  assert_eq(formatted_source("export a := 'hello'\n"), "export a := 'hello'\n")
}

///|
test "formatter keeps backtick assignments" {
  assert_eq(formatted_source("x := `hello`\n"), "x := `hello`\n")
}

///|
test "formatter keeps backtick interpolations" {
  assert_eq(
    formatted_source("foo:\n    echo {{ `echo hi` }}\n"),
    "foo:\n    echo {{ `echo hi` }}\n",
  )
}
