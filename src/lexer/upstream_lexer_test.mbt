///|
fn oracle_source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(25), "justfile", text)
}

///|
fn assert_upstream_tokens(
  text : String,
  expected : Array[@lexer.TokenKind],
) -> Unit raise {
  let input = oracle_source(text)
  let stream = @lexer.lex(input)
  assert_eq(stream.tokens().map(fn(token) { token.kind() }), expected)
  let roundtrip = StringBuilder()
  for token in stream.tokens() {
    roundtrip.write_string(token.lexeme(input))
  }
  assert_eq(roundtrip.to_string(), text)
}

///|
test "just 1.57.0 key token oracle corpus" {
  let mut covered = 0
  assert_upstream_tokens("foo", [Identifier, Eof])
  covered += 1
  assert_upstream_tokens("# hello", [Comment, Eof])
  covered += 1
  assert_upstream_tokens("`echo\necho`", [Backtick, Eof])
  covered += 1
  assert_upstream_tokens("'hello\ngoodbye'", [StringToken, Eof])
  covered += 1
  assert_upstream_tokens("\"\"\"hello\ngoodbye\"\"\"", [StringToken, Eof])
  covered += 1
  assert_upstream_tokens("export foo = ('foo' + 'bar') + `baz`", [
    Identifier,
    Whitespace,
    Identifier,
    Whitespace,
    Equals,
    Whitespace,
    ParenL,
    StringToken,
    Whitespace,
    Plus,
    Whitespace,
    StringToken,
    ParenR,
    Whitespace,
    Plus,
    Whitespace,
    Backtick,
    Eof,
  ])
  covered += 1
  assert_upstream_tokens("#\r\n#asdf\r\n", [Comment, Eol, Comment, Eol, Eof])
  covered += 1
  assert_upstream_tokens("a\n  b\n    c\n  d\n    e\n", [
    Identifier,
    Eol,
    Indent,
    Identifier,
    Eol,
    Indent,
    Identifier,
    Eol,
    Dedent,
    Whitespace,
    Identifier,
    Eol,
    Indent,
    Identifier,
    Eol,
    Dedent,
    Dedent,
    Eof,
  ])
  covered += 1
  assert_upstream_tokens("foo:\n    a\n\nb:\n", [
    Identifier,
    Colon,
    Eol,
    Indent,
    Text,
    Eol,
    Dedent,
    Eol,
    Identifier,
    Colon,
    Eol,
    Eof,
  ])
  covered += 1
  assert_upstream_tokens("hello:\n echo {{`echo hello` + `echo goodbye`}}", [
    Identifier,
    Colon,
    Eol,
    Indent,
    Text,
    InterpolationStart,
    Backtick,
    Whitespace,
    Plus,
    Whitespace,
    Backtick,
    InterpolationEnd,
    Dedent,
    Eof,
  ])
  covered += 1
  assert_upstream_tokens("foo:,#ok\n {{a}}0{{b}}1{{c}}", [
    Identifier,
    Colon,
    Comma,
    Comment,
    Eol,
    Indent,
    InterpolationStart,
    Identifier,
    InterpolationEnd,
    Text,
    InterpolationStart,
    Identifier,
    InterpolationEnd,
    Text,
    InterpolationStart,
    Identifier,
    InterpolationEnd,
    Dedent,
    Eof,
  ])
  covered += 1
  assert_upstream_tokens("[\n](\n){\n}", [
    BracketL,
    Whitespace,
    BracketR,
    ParenL,
    Whitespace,
    ParenR,
    BraceL,
    Whitespace,
    BraceR,
    Eof,
  ])
  covered += 1
  assert_upstream_tokens("f'{{foo}}bar{{baz}}'", [
    Identifier,
    FormatStringStart,
    Identifier,
    FormatStringContinue,
    Identifier,
    FormatStringEnd,
    Eof,
  ])
  covered += 1
  assert_upstream_tokens("f '{{foo}}' g'{{foo}}'", [
    Identifier,
    Whitespace,
    StringToken,
    Whitespace,
    Identifier,
    StringToken,
    Eof,
  ])
  covered += 1
  assert_upstream_tokens("foo := f'{{'foo'}}{{'bar'}}'\nbar:", [
    Identifier,
    Whitespace,
    ColonEquals,
    Whitespace,
    Identifier,
    FormatStringStart,
    StringToken,
    FormatStringContinue,
    StringToken,
    FormatStringEnd,
    Eol,
    Identifier,
    Colon,
    Eof,
  ])
  covered += 1
  assert_upstream_tokens("foo:\n echo FOO\n\nfoo:", [
    Identifier,
    Colon,
    Eol,
    Indent,
    Text,
    Eol,
    Dedent,
    Eol,
    Identifier,
    Colon,
    Eof,
  ])
  covered += 1
  assert_eq(covered, 16)
}

///|
test "just 1.57.0 key error oracle corpus" {
  let mixed = oracle_source("a\n\t echo hello")
  try @lexer.lex(mixed) catch {
    MixedLeadingWhitespace(whitespace="\t ", span~) => {
      assert_eq(span.start_byte(), 2)
      assert_eq(span.length(), 2)
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected mixed indentation")
  }
  let bad_dedent = oracle_source("a\n foo\n   bar\n  baz")
  try @lexer.lex(bad_dedent) catch {
    InconsistentLeadingWhitespace(expected="   ", found="  ", span~) =>
      assert_eq(span.start_byte(), 14)
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected inconsistent indentation")
  }
  let interpolation = oracle_source("a:\n echo {{foo(")
  try @lexer.lex(interpolation) catch {
    UnterminatedInterpolation(span~) => {
      assert_eq(span.start_byte(), 9)
      assert_eq(span.length(), 2)
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unterminated interpolation")
  }
  let carriage_return = oracle_source("foo\rbar")
  try @lexer.lex(carriage_return) catch {
    UnpairedCarriageReturn(span~) => assert_eq(span.start_byte(), 3)
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unpaired carriage return")
  }
  let ampersand = oracle_source("&%")
  try @lexer.lex(ampersand) catch {
    UnexpectedCharacter(expected="&", found="%", span~) => {
      assert_eq(span.start_byte(), 1)
      assert_eq(span.length(), 1)
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unexpected character")
  }
}
