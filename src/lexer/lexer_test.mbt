///|
fn source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(20), "justfile", text)
}

///|
fn kinds(stream : @lexer.TokenStream) -> Array[@lexer.TokenKind] {
  stream.tokens().map(fn(token) { token.kind() })
}

///|
fn lexemes(
  stream : @lexer.TokenStream,
  input : @source.Source,
) -> Array[String] raise {
  stream.tokens().map(fn(token) raise { token.lexeme(input) })
}

///|
test "normal tokens preserve upstream kinds, lexemes, and byte spans" {
  let input = source("export foo = (bar-baz + 2) # hi\n")
  try @lexer.lex(input) catch {
    @lexer.UnknownStartOfToken(start="2", span~) => {
      assert_eq(span.start_byte(), 24)
      assert_eq(span.end_byte(), 25)
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("digits cannot start just identifiers")
  }
  let valid = source("export foo = (bar-baz + qux) # hi\n")
  let stream = @lexer.lex(valid)
  assert_eq(kinds(stream), [
    @lexer.Identifier,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.Whitespace,
    @lexer.Equals,
    @lexer.Whitespace,
    @lexer.ParenL,
    @lexer.Identifier,
    @lexer.Whitespace,
    @lexer.Plus,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.ParenR,
    @lexer.Whitespace,
    @lexer.Comment,
    @lexer.Eol,
    @lexer.Eof,
  ])
  assert_eq(lexemes(stream, valid), [
    "export", " ", "foo", " ", "=", " ", "(", "bar-baz", " ", "+", " ", "qux", ")",
    " ", "# hi", "\n", "",
  ])
  let tokens = stream.tokens()
  for index = 1; index < tokens.length(); index = index + 1 {
    assert_true(
      tokens[index - 1].span().end_byte() <= tokens[index].span().start_byte(),
    )
  }
}

///|
test "operators, comments, BOM, CRLF, and continued lines" {
  let input = source(
    "\u{feff}a:=b::c && d||e != f !~ g == h =~ i ++ j\\\r\n  k\r\n",
  )
  let stream = @lexer.lex(input)
  assert_eq(kinds(stream), [
    @lexer.ByteOrderMark,
    @lexer.Identifier,
    @lexer.ColonEquals,
    @lexer.Identifier,
    @lexer.ColonColon,
    @lexer.Identifier,
    @lexer.Whitespace,
    @lexer.AmpersandAmpersand,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.BarBar,
    @lexer.Identifier,
    @lexer.Whitespace,
    @lexer.BangEquals,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.Whitespace,
    @lexer.BangTilde,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.Whitespace,
    @lexer.EqualsEquals,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.Whitespace,
    @lexer.EqualsTilde,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.Whitespace,
    @lexer.PlusPlus,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.Eol,
    @lexer.Eof,
  ])
}

///|
test "keywords remain identifiers and use an explicit lookup table" {
  let input = source("set shell export working-directory ordinary")
  let stream = @lexer.lex(input)
  assert_eq(kinds(stream), [
    @lexer.Identifier,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.Eof,
  ])
  assert_eq(@lexer.Keyword::from_lexeme("set"), Some(@lexer.Set))
  assert_eq(
    @lexer.Keyword::from_lexeme("working-directory"),
    Some(@lexer.WorkingDirectory),
  )
  assert_eq(@lexer.Keyword::from_lexeme("ordinary"), None)
  assert_eq(@lexer.WindowsPowershell.lexeme(), "windows-powershell")
}

///|
test "delimiter and digraph failures preserve upstream error spans" {
  let unmatched = source("(]")
  try @lexer.lex(unmatched) catch {
    @lexer.MismatchedClosingDelimiter(
      open=@lexer.Paren,
      close=@lexer.Bracket,
      open_line=1,
      span~
    ) => assert_eq(span, @source.Span::new(unmatched.id(), 1, 1))
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected mismatched delimiter")
  }
  let ampersand = source("&")
  try @lexer.lex(ampersand) catch {
    @lexer.UnexpectedEndOfToken(span~, ..) =>
      assert_eq(span, ampersand.eof_span())
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected digraph error")
  }
}
