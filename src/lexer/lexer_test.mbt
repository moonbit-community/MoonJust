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

///|
test "raw, cooked, backtick, and triple strings match upstream boundaries" {
  let input = source(
    "'raw \\\\ value' \"cooked \\\" value\" `echo \\\\ ok` '''multi\nraw''' \"\"\"multi\n\\\"quoted\\\"\"\"\"",
  )
  let stream = @lexer.lex(input)
  assert_eq(kinds(stream), [
    @lexer.StringToken,
    @lexer.Whitespace,
    @lexer.StringToken,
    @lexer.Whitespace,
    @lexer.Backtick,
    @lexer.Whitespace,
    @lexer.StringToken,
    @lexer.Whitespace,
    @lexer.StringToken,
    @lexer.Eof,
  ])
  assert_eq(lexemes(stream, input), [
    "'raw \\\\ value'", " ", "\"cooked \\\" value\"", " ", "`echo \\\\ ok`", " ",
    "'''multi\nraw'''", " ", "\"\"\"multi\n\\\"quoted\\\"\"\"\"", "",
  ])
}

///|
test "Unicode and parser-level escape errors remain one cooked token" {
  let input = source("\"中🙂\\u{1F642}\\q\"")
  let stream = @lexer.lex(input)
  assert_eq(kinds(stream), [@lexer.StringToken, @lexer.Eof])
  assert_eq(stream.tokens()[0].span().end_byte(), input.length())
  assert_eq(stream.tokens()[0].lexeme(input), "\"中🙂\\u{1F642}\\q\"")
}

///|
test "unterminated strings highlight only their opening delimiter" {
  let cooked = source("name = \"unterminated")
  try @lexer.lex(cooked) catch {
    @lexer.UnterminatedString(span~) => {
      assert_eq(span.start_byte(), 7)
      assert_eq(span.length(), 1)
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unterminated string")
  }
  let backtick = source("```unterminated")
  try @lexer.lex(backtick) catch {
    @lexer.UnterminatedBacktick(span~) => assert_eq(span.length(), 3)
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unterminated backtick")
  }
}

///|
test "nested indentation emits source-backed indents and synthetic dedents" {
  let input = source("a\n  b\n    c\n  d\n")
  let stream = @lexer.lex(input)
  assert_eq(kinds(stream), [
    @lexer.Identifier,
    @lexer.Eol,
    @lexer.Indent,
    @lexer.Identifier,
    @lexer.Eol,
    @lexer.Indent,
    @lexer.Identifier,
    @lexer.Eol,
    @lexer.Dedent,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.Eol,
    @lexer.Dedent,
    @lexer.Eof,
  ])
  let tokens = stream.tokens()
  assert_eq(tokens[2].lexeme(input), "  ")
  assert_eq(tokens[5].lexeme(input), "    ")
  assert_true(tokens[8].span().is_empty())
  assert_true(tokens[12].span().is_empty())
}

///|
test "blank lines, CRLF, delimiters, and EOF preserve indentation behavior" {
  let input = source("a\r\n  b\r\n\t\t\r\n  c\r\n\r\nd")
  let stream = @lexer.lex(input)
  assert_eq(kinds(stream), [
    @lexer.Identifier,
    @lexer.Eol,
    @lexer.Indent,
    @lexer.Identifier,
    @lexer.Eol,
    @lexer.Whitespace,
    @lexer.Eol,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.Eol,
    @lexer.Dedent,
    @lexer.Eol,
    @lexer.Identifier,
    @lexer.Eof,
  ])
  let delimited = source("[\n  value\n]")
  assert_eq(kinds(@lexer.lex(delimited)), [
    @lexer.BracketL,
    @lexer.Whitespace,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.Whitespace,
    @lexer.BracketR,
    @lexer.Eof,
  ])
  let eof = source("a\n  b")
  assert_eq(kinds(@lexer.lex(eof)), [
    @lexer.Identifier,
    @lexer.Eol,
    @lexer.Indent,
    @lexer.Identifier,
    @lexer.Dedent,
    @lexer.Eof,
  ])
}

///|
test "mixed and inconsistent leading whitespace are typed" {
  let mixed = source("a\n \tb")
  try @lexer.lex(mixed) catch {
    @lexer.MixedLeadingWhitespace(whitespace=" \t", span~) => {
      assert_eq(span.start_byte(), 2)
      assert_eq(span.length(), 2)
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected mixed leading whitespace")
  }
  let inconsistent = source("a\n foo\n   bar\n  baz")
  try @lexer.lex(inconsistent) catch {
    @lexer.InconsistentLeadingWhitespace(expected="   ", found="  ", span~) =>
      assert_eq(span.start_byte(), 14)
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected inconsistent leading whitespace")
  }
}

///|
test "recipe bodies preserve text, prefixes, blank lines, and brace escapes" {
  let input = source(
    "build: dependency\n  @echo first\n  -echo {{{{literal\n\nnext:\n\techo tab",
  )
  let stream = @lexer.lex(input)
  assert_eq(kinds(stream), [
    @lexer.Identifier,
    @lexer.Colon,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.Eol,
    @lexer.Indent,
    @lexer.Text,
    @lexer.Eol,
    @lexer.Whitespace,
    @lexer.Text,
    @lexer.Eol,
    @lexer.Dedent,
    @lexer.Eol,
    @lexer.Identifier,
    @lexer.Colon,
    @lexer.Eol,
    @lexer.Indent,
    @lexer.Text,
    @lexer.Dedent,
    @lexer.Eof,
  ])
  assert_eq(stream.tokens()[6].lexeme(input), "@echo first")
  assert_eq(stream.tokens()[9].lexeme(input), "-echo {{{{literal")
  assert_eq(stream.tokens()[17].lexeme(input), "echo tab")
}

///|
test "recipe interpolation switches between text and normal token modes" {
  let input = source("hello:\n echo {{`echo hello` + (name)}} tail {{}}")
  let stream = @lexer.lex(input)
  assert_eq(kinds(stream), [
    @lexer.Identifier,
    @lexer.Colon,
    @lexer.Eol,
    @lexer.Indent,
    @lexer.Text,
    @lexer.InterpolationStart,
    @lexer.Backtick,
    @lexer.Whitespace,
    @lexer.Plus,
    @lexer.Whitespace,
    @lexer.ParenL,
    @lexer.Identifier,
    @lexer.ParenR,
    @lexer.InterpolationEnd,
    @lexer.Text,
    @lexer.InterpolationStart,
    @lexer.InterpolationEnd,
    @lexer.Dedent,
    @lexer.Eof,
  ])
  assert_eq(stream.tokens()[4].lexeme(input), "echo ")
  assert_eq(stream.tokens()[14].lexeme(input), " tail ")
}

///|
test "format strings emit start, continue, and end segments" {
  let input = source(
    "f'' f'{{foo}}bar{{baz}}' f '{{plain}}' g'{{plain}}' f'''{{'x'}}'''",
  )
  let stream = @lexer.lex(input)
  assert_eq(kinds(stream), [
    @lexer.Identifier,
    @lexer.StringToken,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.FormatStringStart,
    @lexer.Identifier,
    @lexer.FormatStringContinue,
    @lexer.Identifier,
    @lexer.FormatStringEnd,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.Whitespace,
    @lexer.StringToken,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.StringToken,
    @lexer.Whitespace,
    @lexer.Identifier,
    @lexer.FormatStringStart,
    @lexer.StringToken,
    @lexer.FormatStringEnd,
    @lexer.Eof,
  ])
  assert_eq(stream.tokens()[4].lexeme(input), "'{{")
  assert_eq(stream.tokens()[6].lexeme(input), "}}bar{{")
  assert_eq(stream.tokens()[8].lexeme(input), "}}'")
  assert_eq(stream.tokens()[18].lexeme(input), "'''{{")
  assert_eq(stream.tokens()[20].lexeme(input), "}}'''")
}

///|
test "unterminated and nested interpolation errors retain opening spans" {
  let unterminated = source("foo:\n echo {{ value")
  try @lexer.lex(unterminated) catch {
    @lexer.UnterminatedInterpolation(span~) => {
      assert_eq(span.start_byte(), 11)
      assert_eq(span.length(), 2)
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unterminated interpolation")
  }
  let mismatched = source("foo:\n echo {{ value(}}")
  try @lexer.lex(mismatched) catch {
    @lexer.MismatchedClosingDelimiter(
      open=@lexer.Paren,
      close=@lexer.Brace,
      span~,
      ..
    ) => assert_true(span.is_empty())
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected nested delimiter mismatch")
  }
}
