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
  assert_eq(stream.tokens()[expected.length()].kind(), Eof)
}

///|
test "upstream lexer::tests::indent_recipe_dedent_indent" {
  assert_tokens_remaining("a\n  b:\n    c\n  d\n    e\n", [
    (Identifier, "a"),
    (Eol, "\n"),
    (Indent, "  "),
    (Identifier, "b"),
    (Colon, ":"),
    (Eol, "\n"),
    (Indent, "    "),
    (Text, "c"),
    (Eol, "\n"),
    (Dedent, ""),
    (Whitespace, "  "),
    (Identifier, "d"),
    (Eol, "\n"),
    (Indent, "    "),
    (Identifier, "e"),
    (Eol, "\n"),
    (Dedent, ""),
    (Dedent, ""),
  ])
}

///|
test "upstream lexer::tests::tokenize_multiple" {
  assert_tokens_remaining(
    "\nhello:\n  a\n  b\n\n  c\n\n  d\n\n# hello\nbob:\n  frank\n\n",
    [
      (Eol, "\n"),
      (Identifier, "hello"),
      (Colon, ":"),
      (Eol, "\n"),
      (Indent, "  "),
      (Text, "a"),
      (Eol, "\n"),
      (Whitespace, "  "),
      (Text, "b"),
      (Eol, "\n"),
      (Eol, "\n"),
      (Whitespace, "  "),
      (Text, "c"),
      (Eol, "\n"),
      (Eol, "\n"),
      (Whitespace, "  "),
      (Text, "d"),
      (Eol, "\n"),
      (Dedent, ""),
      (Eol, "\n"),
      (Comment, "# hello"),
      (Eol, "\n"),
      (Identifier, "bob"),
      (Colon, ":"),
      (Eol, "\n"),
      (Indent, "  "),
      (Text, "frank"),
      (Eol, "\n"),
      (Eol, "\n"),
      (Dedent, ""),
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
    (Identifier, "foo"),
    (Eol, "\n"),
    (Identifier, "bar-bob"),
    (Eol, "\n"),
    (Identifier, "b-bob_asdfAAAA"),
    (Eol, "\n"),
    (Identifier, "test123"),
    (Eol, "\n"),
  ])
}

///|
test "upstream lexer::tests::tokenize_comment_before_variable" {
  assert_tokens_remaining("#\nA='1'\necho:\n  echo {{A}}\n", [
    (Comment, "#"),
    (Eol, "\n"),
    (Identifier, "A"),
    (Equals, "="),
    (StringToken, "'1'"),
    (Eol, "\n"),
    (Identifier, "echo"),
    (Colon, ":"),
    (Eol, "\n"),
    (Indent, "  "),
    (Text, "echo "),
    (InterpolationStart, "{{"),
    (Identifier, "A"),
    (InterpolationEnd, "}}"),
    (Eol, "\n"),
    (Dedent, ""),
  ])
}

///|
test "upstream lexer::tests::tokenize_empty_lines" {
  assert_tokens_remaining(
    "\n# this does something\nhello:\n  asdf\n  bsdf\n\n  csdf\n\n  dsdf # whatever\n\n# yolo\n",
    [
      (Eol, "\n"),
      (Comment, "# this does something"),
      (Eol, "\n"),
      (Identifier, "hello"),
      (Colon, ":"),
      (Eol, "\n"),
      (Indent, "  "),
      (Text, "asdf"),
      (Eol, "\n"),
      (Whitespace, "  "),
      (Text, "bsdf"),
      (Eol, "\n"),
      (Eol, "\n"),
      (Whitespace, "  "),
      (Text, "csdf"),
      (Eol, "\n"),
      (Eol, "\n"),
      (Whitespace, "  "),
      (Text, "dsdf # whatever"),
      (Eol, "\n"),
      (Dedent, ""),
      (Eol, "\n"),
      (Comment, "# yolo"),
      (Eol, "\n"),
    ],
  )
}

///|
test "upstream lexer::tests::tokenize_continued_indent" {
  assert_tokens_remaining("hello:\n  foo\n\n  bar\n\nbaz\n", [
    (Identifier, "hello"),
    (Colon, ":"),
    (Eol, "\n"),
    (Indent, "  "),
    (Text, "foo"),
    (Eol, "\n"),
    (Eol, "\n"),
    (Whitespace, "  "),
    (Text, "bar"),
    (Eol, "\n"),
    (Dedent, ""),
    (Eol, "\n"),
    (Identifier, "baz"),
    (Eol, "\n"),
  ])
}

///|
test "upstream lexer::tests::tokenize_indented_block" {
  assert_tokens_remaining("foo:\n  a\n  b\n  c\n", [
    (Identifier, "foo"),
    (Colon, ":"),
    (Eol, "\n"),
    (Indent, "  "),
    (Text, "a"),
    (Eol, "\n"),
    (Whitespace, "  "),
    (Text, "b"),
    (Eol, "\n"),
    (Whitespace, "  "),
    (Text, "c"),
    (Eol, "\n"),
    (Dedent, ""),
  ])
}

///|
test "upstream lexer::tests::indented_normal" {
  assert_tokens_remaining("a\n  b\n  c\n", [
    (Identifier, "a"),
    (Eol, "\n"),
    (Indent, "  "),
    (Identifier, "b"),
    (Eol, "\n"),
    (Whitespace, "  "),
    (Identifier, "c"),
    (Eol, "\n"),
    (Dedent, ""),
  ])
}

///|
test "upstream lexer::tests::indented_normal_multiple" {
  assert_tokens_remaining("a\n  b\n    c\n", [
    (Identifier, "a"),
    (Eol, "\n"),
    (Indent, "  "),
    (Identifier, "b"),
    (Eol, "\n"),
    (Indent, "    "),
    (Identifier, "c"),
    (Eol, "\n"),
    (Dedent, ""),
    (Dedent, ""),
  ])
}

///|
test "upstream keyword::tests::keyword_case" {
  assert_eq(Keyword::X.lexeme(), "x")
  assert_eq(Keyword::IgnoreComments.lexeme(), "ignore-comments")
  assert_true(Keyword::from_lexeme("x") is Some(X))
  assert_true(Keyword::from_lexeme("ignore-comments") is Some(IgnoreComments))
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
    (Identifier, "bob"),
    (Eol, "\n"),
    (Eol, "\n"),
    (Identifier, "hello"),
    (Whitespace, " "),
    (Identifier, "blah"),
    (Whitespace, " "),
    (Identifier, "blah"),
    (Whitespace, " "),
    (Identifier, "blah"),
    (Whitespace, " "),
    (Colon, ":"),
    (Whitespace, " "),
    (Identifier, "a"),
    (Whitespace, " "),
    (Identifier, "b"),
    (Whitespace, " "),
    (Identifier, "c"),
    (Whitespace, " "),
    (Comment, "#whatever"),
    (Eol, "\n"),
  ])
}

///|
test "upstream lexer::tests::indent_indent_dedent_indent" {
  assert_tokens_remaining("a\n  b\n    c\n  d\n    e\n", [
    (Identifier, "a"),
    (Eol, "\n"),
    (Indent, "  "),
    (Identifier, "b"),
    (Eol, "\n"),
    (Indent, "    "),
    (Identifier, "c"),
    (Eol, "\n"),
    (Dedent, ""),
    (Whitespace, "  "),
    (Identifier, "d"),
    (Eol, "\n"),
    (Indent, "    "),
    (Identifier, "e"),
    (Eol, "\n"),
    (Dedent, ""),
    (Dedent, ""),
  ])
}

///|
test "upstream lexer::tests::indented_block_followed_by_blank" {
  assert_tokens_remaining("foo:\n    a\n\nb:\n", [
    (Identifier, "foo"),
    (Colon, ":"),
    (Eol, "\n"),
    (Indent, "    "),
    (Text, "a"),
    (Eol, "\n"),
    (Dedent, ""),
    (Eol, "\n"),
    (Identifier, "b"),
    (Colon, ":"),
    (Eol, "\n"),
  ])
}

///|
test "upstream lexer::tests::indented_block_followed_by_item" {
  assert_tokens_remaining("foo:\n  a\nb:\n", [
    (Identifier, "foo"),
    (Colon, ":"),
    (Eol, "\n"),
    (Indent, "  "),
    (Text, "a"),
    (Eol, "\n"),
    (Dedent, ""),
    (Identifier, "b"),
    (Colon, ":"),
    (Eol, "\n"),
  ])
}

///|
test "upstream lexer::tests::indented_blocks" {
  assert_tokens_remaining(
    "b: a\n  @mv a b\n\na:\n  @touch F\n  @touch a\n\nd: c\n  @rm c\n\nc: b\n  @mv b c\n",
    [
      (Identifier, "b"),
      (Colon, ":"),
      (Whitespace, " "),
      (Identifier, "a"),
      (Eol, "\n"),
      (Indent, "  "),
      (Text, "@mv a b"),
      (Eol, "\n"),
      (Dedent, ""),
      (Eol, "\n"),
      (Identifier, "a"),
      (Colon, ":"),
      (Eol, "\n"),
      (Indent, "  "),
      (Text, "@touch F"),
      (Eol, "\n"),
      (Whitespace, "  "),
      (Text, "@touch a"),
      (Eol, "\n"),
      (Dedent, ""),
      (Eol, "\n"),
      (Identifier, "d"),
      (Colon, ":"),
      (Whitespace, " "),
      (Identifier, "c"),
      (Eol, "\n"),
      (Indent, "  "),
      (Text, "@rm c"),
      (Eol, "\n"),
      (Dedent, ""),
      (Eol, "\n"),
      (Identifier, "c"),
      (Colon, ":"),
      (Whitespace, " "),
      (Identifier, "b"),
      (Eol, "\n"),
      (Indent, "  "),
      (Text, "@mv b c"),
      (Eol, "\n"),
      (Dedent, ""),
    ],
  )
}

///|
test "upstream lexer::tests::indented_block" {
  assert_tokens_remaining("foo:\n  a\n  b\n  c\n", [
    (Identifier, "foo"),
    (Colon, ":"),
    (Eol, "\n"),
    (Indent, "  "),
    (Text, "a"),
    (Eol, "\n"),
    (Whitespace, "  "),
    (Text, "b"),
    (Eol, "\n"),
    (Whitespace, "  "),
    (Text, "c"),
    (Eol, "\n"),
    (Dedent, ""),
  ])
}

///|
test "upstream lexer::tests::brace_escape" {
  assert_tokens_remaining("foo:\n  {{{{\n", [
    (Identifier, "foo"),
    (Colon, ":"),
    (Eol, "\n"),
    (Indent, "  "),
    (Text, "{{{{"),
    (Eol, "\n"),
    (Dedent, ""),
  ])
}

///|
test "upstream lexer::tests::tokenize_recipe_interpolation_eol" {
  assert_tokens_remaining("foo: # some comment\n {{hello}}\n", [
    (Identifier, "foo"),
    (Colon, ":"),
    (Whitespace, " "),
    (Comment, "# some comment"),
    (Eol, "\n"),
    (Indent, " "),
    (InterpolationStart, "{{"),
    (Identifier, "hello"),
    (InterpolationEnd, "}}"),
    (Eol, "\n"),
    (Dedent, ""),
  ])
}

///|
test "upstream lexer::tests::tokenize_order" {
  assert_tokens_remaining(
    "b: a\n  @mv a b\n\na:\n  @touch F\n  @touch a\n\nd: c\n  @rm c\n\nc: b\n  @mv b c\n",
    [
      (Identifier, "b"),
      (Colon, ":"),
      (Whitespace, " "),
      (Identifier, "a"),
      (Eol, "\n"),
      (Indent, "  "),
      (Text, "@mv a b"),
      (Eol, "\n"),
      (Dedent, ""),
      (Eol, "\n"),
      (Identifier, "a"),
      (Colon, ":"),
      (Eol, "\n"),
      (Indent, "  "),
      (Text, "@touch F"),
      (Eol, "\n"),
      (Whitespace, "  "),
      (Text, "@touch a"),
      (Eol, "\n"),
      (Dedent, ""),
      (Eol, "\n"),
      (Identifier, "d"),
      (Colon, ":"),
      (Whitespace, " "),
      (Identifier, "c"),
      (Eol, "\n"),
      (Indent, "  "),
      (Text, "@rm c"),
      (Eol, "\n"),
      (Dedent, ""),
      (Eol, "\n"),
      (Identifier, "c"),
      (Colon, ":"),
      (Whitespace, " "),
      (Identifier, "b"),
      (Eol, "\n"),
      (Indent, "  "),
      (Text, "@mv b c"),
      (Eol, "\n"),
      (Dedent, ""),
    ],
  )
}
