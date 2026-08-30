///|
fn assert_tokens(
  text : String,
  expected : Array[(TokenKind, String)],
) -> Unit raise {
  let source = @source.Source::from_text(
    @source.SourceId::new(803),
    "justfile",
    text,
  )
  let stream = @lexer.lex(source)
  assert_eq(stream.length(), expected.length() + 1)
  for index, pair in expected {
    let token = stream.tokens()[index]
    assert_eq(token.kind(), pair.0)
    assert_eq(token.lexeme(source), pair.1)
  }
  assert_eq(stream.tokens()[expected.length()].kind(), @lexer.TokenKind::Eof)
}

///|
test "lexer name_new" {
  assert_tokens("foo", [(TokenKind::Identifier, "foo")])
}

///|
test "lexer comment" {
  assert_tokens("# hello", [(TokenKind::Comment, "# hello")])
}

///|
test "lexer plus_plus" {
  assert_tokens("++", [(TokenKind::PlusPlus, "++")])
}

///|
test "lexer equals" {
  assert_tokens("=", [(TokenKind::Equals, "=")])
}

///|
test "lexer equals_equals" {
  assert_tokens("==", [(TokenKind::EqualsEquals, "==")])
}

///|
test "lexer multiple_recipes" {
  assert_tokens("a:\n  foo\nb:", [
    (TokenKind::Identifier, "a"),
    (TokenKind::Colon, ":"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "  "),
    (TokenKind::Text, "foo"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Dedent, ""),
    (TokenKind::Identifier, "b"),
    (TokenKind::Colon, ":"),
  ])
}
