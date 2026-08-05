///|
fn formatter_source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(35), "justfile", text)
}

///|
test "formatter is idempotent and canonicalizes recipe indentation" {
  let source = formatter_source("foo:\n  echo hi\n")
  let once = @formatter.format_source(source)
  assert_eq(once, "foo:\n    echo hi\n")
  let twice = @formatter.format_source(formatter_source(once))
  assert_eq(twice, once)
  assert_true(@formatter.is_formatted(formatter_source(once)))
  assert_true(@formatter.check(source).changed())
}

///|
test "formatter preserves expression structure and attributes" {
  let source = formatter_source("[private]\nfoo x: echo\n")
  let rendered = @formatter.format_source(source)
  assert_eq(rendered, "[private]\nfoo x: echo\n")
}
