///|
test "parser returns typed results for malformed and adversarial grammar inputs" {
  let cases = [
    ":", "foo :=", "foo: &&", "foo: (bar", "foo: [bar", "set unknown", "[unknown]\nfoo:",
    "foo x + y z:", "import \"unterminated", "foo:\n  {{ if x { y } }}", "foo:\n  {{",
    "if x { y } else",
  ]
  for text in cases {
    let source = @source.Source::from_text(
      @source.SourceId::new(38),
      "case",
      text,
    )
    try @parser.parse(source) catch {
      _ => ()
    } noraise {
      _ => ()
    }
  }
}

///|
test "parser resource limits reject deep and large syntax without host access" {
  let mut text = "a"
  for _ in 0..<32 {
    text = "(" + text + ")"
  }
  let source = @source.Source::from_text(
    @source.SourceId::new(39),
    "deep",
    text,
  )
  let limits = @parser.ParserLimits::new(8, 1000, 8)
  try @parser.parse_expression(source, limits~) catch {
    RecursionLimitExceeded(limit=8, ..) => ()
    _ => fail("expected parser recursion guard")
  } noraise {
    _ => fail("expected parser recursion guard")
  }
}
