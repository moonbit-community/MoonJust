///|
fn assert_upstream_tokens(
  text : String,
  expected : Array[(TokenKind, String?)],
) -> Unit raise {
  let source = @source.Source::from_text(
    @source.SourceId::new(860),
    "justfile",
    text,
  )
  let stream = lex(source)
  assert_eq(stream.length(), expected.length() + 1)
  for index, pair in expected {
    let token = stream.tokens()[index]
    assert_eq(token.kind(), pair.0)
    match pair.1 {
      Some(lexeme) => assert_eq(token.lexeme(source), lexeme)
      None => ()
    }
  }
  assert_eq(stream.tokens()[expected.length()].kind(), Eof)
}
