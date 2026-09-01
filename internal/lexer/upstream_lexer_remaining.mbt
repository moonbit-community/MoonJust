///|
fn assert_tokens_remaining(
  text : String,
  expected : Array[(TokenKind, String)],
) -> Unit raise {
  let source = @source.Source::from_text(
    @source.SourceId::new(897),
    "justfile",
    text,
  )
  let stream = lex(source)
  assert_eq(stream.length(), expected.length() + 1)
  for index, pair in expected {
    let token = stream.tokens()[index]
    assert_eq(token.kind(), pair.0)
    assert_eq(token.lexeme(source), pair.1)
  }
  assert_eq(stream.tokens()[expected.length()].kind(), TokenKind::Eof)
}

///|
test "upstream lexer::tests::indent_recipe_dedent_indent" {
  assert_tokens_remaining("a\n  b:\n    c\n  d\n    e\n", [
    (TokenKind::Identifier, "a"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "  "),
    (TokenKind::Identifier, "b"),
    (TokenKind::Colon, ":"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "    "),
    (TokenKind::Text, "c"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Dedent, ""),
    (TokenKind::Whitespace, "  "),
    (TokenKind::Identifier, "d"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "    "),
    (TokenKind::Identifier, "e"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Dedent, ""),
    (TokenKind::Dedent, ""),
  ])
}

///|
test "upstream lexer::tests::tokenize_multiple" {
  assert_tokens_remaining(
    "\nhello:\n  a\n  b\n\n  c\n\n  d\n\n# hello\nbob:\n  frank\n\n",
    [
      (TokenKind::Eol, "\n"),
      (TokenKind::Identifier, "hello"),
      (TokenKind::Colon, ":"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Indent, "  "),
      (TokenKind::Text, "a"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Whitespace, "  "),
      (TokenKind::Text, "b"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Whitespace, "  "),
      (TokenKind::Text, "c"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Whitespace, "  "),
      (TokenKind::Text, "d"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Dedent, ""),
      (TokenKind::Eol, "\n"),
      (TokenKind::Comment, "# hello"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Identifier, "bob"),
      (TokenKind::Colon, ":"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Indent, "  "),
      (TokenKind::Text, "frank"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Dedent, ""),
    ],
  )
}

///|
test "upstream lexer::tests::presume_error" {
  let source = @source.Source::from_text(
    @source.SourceId::new(898),
    "justfile",
    "&x",
  )
  try lex(source) catch {
    UnexpectedCharacter(expected~, found~, span~) => {
      assert_eq(expected, "&")
      assert_eq(found, "x")
      assert_eq(span.start_byte(), 1)
      assert_eq(span.length(), 1)
      let error = LexerError::UnexpectedCharacter(expected~, found~, span~)
      assert_eq(error.code(), "MJ-LEX-0003")
      assert_eq(error.message(), "expected character `&`")
    }
    error => fail("unexpected lexer error: \{Repr(error)}")
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::tokenize_names" {
  assert_tokens_remaining("foo\nbar-bob\nb-bob_asdfAAAA\ntest123\n", [
    (TokenKind::Identifier, "foo"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Identifier, "bar-bob"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Identifier, "b-bob_asdfAAAA"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Identifier, "test123"),
    (TokenKind::Eol, "\n"),
  ])
}

///|
test "upstream lexer::tests::tokenize_comment_before_variable" {
  assert_tokens_remaining("#\nA='1'\necho:\n  echo {{A}}\n", [
    (TokenKind::Comment, "#"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Identifier, "A"),
    (TokenKind::Equals, "="),
    (TokenKind::StringToken, "'1'"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Identifier, "echo"),
    (TokenKind::Colon, ":"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "  "),
    (TokenKind::Text, "echo "),
    (TokenKind::InterpolationStart, "{{"),
    (TokenKind::Identifier, "A"),
    (TokenKind::InterpolationEnd, "}}"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Dedent, ""),
  ])
}

///|
test "upstream lexer::tests::tokenize_empty_lines" {
  assert_tokens_remaining(
    "\n# this does something\nhello:\n  asdf\n  bsdf\n\n  csdf\n\n  dsdf # whatever\n\n# yolo\n",
    [
      (TokenKind::Eol, "\n"),
      (TokenKind::Comment, "# this does something"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Identifier, "hello"),
      (TokenKind::Colon, ":"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Indent, "  "),
      (TokenKind::Text, "asdf"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Whitespace, "  "),
      (TokenKind::Text, "bsdf"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Whitespace, "  "),
      (TokenKind::Text, "csdf"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Whitespace, "  "),
      (TokenKind::Text, "dsdf # whatever"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Dedent, ""),
      (TokenKind::Eol, "\n"),
      (TokenKind::Comment, "# yolo"),
      (TokenKind::Eol, "\n"),
    ],
  )
}

///|
test "upstream lexer::tests::tokenize_continued_indent" {
  assert_tokens_remaining("hello:\n  foo\n\n  bar\n\nbaz\n", [
    (TokenKind::Identifier, "hello"),
    (TokenKind::Colon, ":"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "  "),
    (TokenKind::Text, "foo"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Whitespace, "  "),
    (TokenKind::Text, "bar"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Dedent, ""),
    (TokenKind::Eol, "\n"),
    (TokenKind::Identifier, "baz"),
    (TokenKind::Eol, "\n"),
  ])
}

///|
test "upstream lexer::tests::tokenize_indented_block" {
  assert_tokens_remaining("foo:\n  a\n  b\n  c\n", [
    (TokenKind::Identifier, "foo"),
    (TokenKind::Colon, ":"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "  "),
    (TokenKind::Text, "a"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Whitespace, "  "),
    (TokenKind::Text, "b"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Whitespace, "  "),
    (TokenKind::Text, "c"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Dedent, ""),
  ])
}

///|
test "upstream lexer::tests::indented_normal" {
  assert_tokens_remaining("a\n  b\n  c\n", [
    (TokenKind::Identifier, "a"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "  "),
    (TokenKind::Identifier, "b"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Whitespace, "  "),
    (TokenKind::Identifier, "c"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Dedent, ""),
  ])
}

///|
test "upstream lexer::tests::indented_normal_multiple" {
  assert_tokens_remaining("a\n  b\n    c\n", [
    (TokenKind::Identifier, "a"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "  "),
    (TokenKind::Identifier, "b"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "    "),
    (TokenKind::Identifier, "c"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Dedent, ""),
    (TokenKind::Dedent, ""),
  ])
}

///|
test "upstream keyword::tests::keyword_case" {
  assert_eq(Keyword::X.lexeme(), "x")
  assert_eq(Keyword::IgnoreComments.lexeme(), "ignore-comments")
  assert_true(Keyword::from_lexeme("x") is Some(Keyword::X))
  assert_true(
    Keyword::from_lexeme("ignore-comments") is Some(Keyword::IgnoreComments),
  )
}

///|
fn assert_unknown_start(
  text : String,
  expected : String,
  offset : Int,
) -> Unit raise {
  let source = @source.Source::from_text(
    @source.SourceId::new(901),
    "justfile",
    text,
  )
  try lex(source) catch {
    UnknownStartOfToken(start~, span~) => {
      assert_eq(start, expected)
      assert_eq(span.start_byte(), offset)
      assert_eq(span.length(), 1)
    }
    _ => fail("unexpected lexer error")
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::invalid_name_start_dash" {
  assert_unknown_start("-foo", "-", 0)
}

///|
test "upstream lexer::tests::invalid_name_start_digit" {
  assert_unknown_start("0foo", "0", 0)
}

///|
test "upstream lexer::tests::tokenize_unknown" {
  assert_unknown_start("%", "%", 0)
}

///|
test "upstream lexer::tests::unexpected_character_after_at" {
  assert_unknown_start("@%", "%", 1)
}

///|
test "upstream lexer::tests::tokenize_junk" {
  assert_tokens_remaining("bob\n\nhello blah blah blah : a b c #whatever\n", [
    (TokenKind::Identifier, "bob"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Identifier, "hello"),
    (TokenKind::Whitespace, " "),
    (TokenKind::Identifier, "blah"),
    (TokenKind::Whitespace, " "),
    (TokenKind::Identifier, "blah"),
    (TokenKind::Whitespace, " "),
    (TokenKind::Identifier, "blah"),
    (TokenKind::Whitespace, " "),
    (TokenKind::Colon, ":"),
    (TokenKind::Whitespace, " "),
    (TokenKind::Identifier, "a"),
    (TokenKind::Whitespace, " "),
    (TokenKind::Identifier, "b"),
    (TokenKind::Whitespace, " "),
    (TokenKind::Identifier, "c"),
    (TokenKind::Whitespace, " "),
    (TokenKind::Comment, "#whatever"),
    (TokenKind::Eol, "\n"),
  ])
}

///|
test "upstream lexer::tests::indent_indent_dedent_indent" {
  assert_tokens_remaining("a\n  b\n    c\n  d\n    e\n", [
    (TokenKind::Identifier, "a"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "  "),
    (TokenKind::Identifier, "b"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "    "),
    (TokenKind::Identifier, "c"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Dedent, ""),
    (TokenKind::Whitespace, "  "),
    (TokenKind::Identifier, "d"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "    "),
    (TokenKind::Identifier, "e"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Dedent, ""),
    (TokenKind::Dedent, ""),
  ])
}

///|
test "upstream lexer::tests::indented_block_followed_by_blank" {
  assert_tokens_remaining("foo:\n    a\n\nb:\n", [
    (TokenKind::Identifier, "foo"),
    (TokenKind::Colon, ":"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "    "),
    (TokenKind::Text, "a"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Dedent, ""),
    (TokenKind::Eol, "\n"),
    (TokenKind::Identifier, "b"),
    (TokenKind::Colon, ":"),
    (TokenKind::Eol, "\n"),
  ])
}

///|
test "upstream lexer::tests::indented_block_followed_by_item" {
  assert_tokens_remaining("foo:\n  a\nb:\n", [
    (TokenKind::Identifier, "foo"),
    (TokenKind::Colon, ":"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "  "),
    (TokenKind::Text, "a"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Dedent, ""),
    (TokenKind::Identifier, "b"),
    (TokenKind::Colon, ":"),
    (TokenKind::Eol, "\n"),
  ])
}

///|
test "upstream lexer::tests::indented_blocks" {
  assert_tokens_remaining(
    "b: a\n  @mv a b\n\na:\n  @touch F\n  @touch a\n\nd: c\n  @rm c\n\nc: b\n  @mv b c\n",
    [
      (TokenKind::Identifier, "b"),
      (TokenKind::Colon, ":"),
      (TokenKind::Whitespace, " "),
      (TokenKind::Identifier, "a"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Indent, "  "),
      (TokenKind::Text, "@mv a b"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Dedent, ""),
      (TokenKind::Eol, "\n"),
      (TokenKind::Identifier, "a"),
      (TokenKind::Colon, ":"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Indent, "  "),
      (TokenKind::Text, "@touch F"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Whitespace, "  "),
      (TokenKind::Text, "@touch a"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Dedent, ""),
      (TokenKind::Eol, "\n"),
      (TokenKind::Identifier, "d"),
      (TokenKind::Colon, ":"),
      (TokenKind::Whitespace, " "),
      (TokenKind::Identifier, "c"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Indent, "  "),
      (TokenKind::Text, "@rm c"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Dedent, ""),
      (TokenKind::Eol, "\n"),
      (TokenKind::Identifier, "c"),
      (TokenKind::Colon, ":"),
      (TokenKind::Whitespace, " "),
      (TokenKind::Identifier, "b"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Indent, "  "),
      (TokenKind::Text, "@mv b c"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Dedent, ""),
    ],
  )
}

///|
test "upstream lexer::tests::indented_block" {
  assert_tokens_remaining("foo:\n  a\n  b\n  c\n", [
    (TokenKind::Identifier, "foo"),
    (TokenKind::Colon, ":"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "  "),
    (TokenKind::Text, "a"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Whitespace, "  "),
    (TokenKind::Text, "b"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Whitespace, "  "),
    (TokenKind::Text, "c"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Dedent, ""),
  ])
}

///|
test "upstream lexer::tests::brace_escape" {
  assert_tokens_remaining("foo:\n  {{{{\n", [
    (TokenKind::Identifier, "foo"),
    (TokenKind::Colon, ":"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, "  "),
    (TokenKind::Text, "{{{{"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Dedent, ""),
  ])
}

///|
test "upstream lexer::tests::tokenize_recipe_interpolation_eol" {
  assert_tokens_remaining("foo: # some comment\n {{hello}}\n", [
    (TokenKind::Identifier, "foo"),
    (TokenKind::Colon, ":"),
    (TokenKind::Whitespace, " "),
    (TokenKind::Comment, "# some comment"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Indent, " "),
    (TokenKind::InterpolationStart, "{{"),
    (TokenKind::Identifier, "hello"),
    (TokenKind::InterpolationEnd, "}}"),
    (TokenKind::Eol, "\n"),
    (TokenKind::Dedent, ""),
  ])
}

///|
test "upstream lexer::tests::tokenize_order" {
  assert_tokens_remaining(
    "b: a\n  @mv a b\n\na:\n  @touch F\n  @touch a\n\nd: c\n  @rm c\n\nc: b\n  @mv b c\n",
    [
      (TokenKind::Identifier, "b"),
      (TokenKind::Colon, ":"),
      (TokenKind::Whitespace, " "),
      (TokenKind::Identifier, "a"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Indent, "  "),
      (TokenKind::Text, "@mv a b"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Dedent, ""),
      (TokenKind::Eol, "\n"),
      (TokenKind::Identifier, "a"),
      (TokenKind::Colon, ":"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Indent, "  "),
      (TokenKind::Text, "@touch F"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Whitespace, "  "),
      (TokenKind::Text, "@touch a"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Dedent, ""),
      (TokenKind::Eol, "\n"),
      (TokenKind::Identifier, "d"),
      (TokenKind::Colon, ":"),
      (TokenKind::Whitespace, " "),
      (TokenKind::Identifier, "c"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Indent, "  "),
      (TokenKind::Text, "@rm c"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Dedent, ""),
      (TokenKind::Eol, "\n"),
      (TokenKind::Identifier, "c"),
      (TokenKind::Colon, ":"),
      (TokenKind::Whitespace, " "),
      (TokenKind::Identifier, "b"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Indent, "  "),
      (TokenKind::Text, "@mv b c"),
      (TokenKind::Eol, "\n"),
      (TokenKind::Dedent, ""),
    ],
  )
}
