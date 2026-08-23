///|
test "API diagnostics preserve absent and invalid source positions" {
  let source = @source.Source::from_text(
    @source.SourceId::new(8100),
    "coverage.just",
    "x",
  )
  let absent = diagnostic_from_span(source, "MJ-TEST", "message", None)
  assert_eq(absent.source_name(), "coverage.just")
  assert_eq(absent.start_line(), None)
  assert_eq(absent.end_column(), None)

  let invalid_start = try! @source.Span::new(source.id(), 10, 10)
  let start = diagnostic_from_span(
    source,
    "MJ-START",
    "invalid start",
    Some(invalid_start),
  )
  assert_eq(start.start_line(), None)
  assert_eq(start.end_line(), None)

  let invalid_end = try! @source.Span::new(source.id(), 0, 10)
  let end = diagnostic_from_span(
    source,
    "MJ-END",
    "invalid end",
    Some(invalid_end),
  )
  assert_eq(end.start_line(), None)
  assert_eq(end.end_line(), None)
}

///|
test "API formatting errors and lexical ties retain stable diagnostics" {
  assert_eq(lexical_compare("same", "same"), 0)
  assert_true(lexical_compare("a", "aa") < 0)
  try format_text("run:\n  {{\n", source_name="format.just") catch {
    InvalidSource(diagnostics) => {
      assert_eq(diagnostics.length(), 1)
      assert_eq(diagnostics[0].source_name(), "format.just")
    }
  } noraise {
    _ => fail("expected invalid format source")
  }
}
