///|
test "upstream lexer::tests::format_string_wrong_identifier" {
  assert_upstream_tokens("g'{{foo}}'", [
    (TokenKind::Identifier, Some("g")),
    (TokenKind::StringToken, Some("'{{foo}}'")),
  ])
}

///|
test "upstream lexer::tests::indented_format_string_followed_by_recipe" {
  assert_upstream_tokens("foo := f'''{{'foo'}}{{'bar'}}'''\nbar:", [
    (TokenKind::Identifier, Some("foo")),
    (TokenKind::Whitespace, Some(" ")),
    (TokenKind::ColonEquals, Some(":=")),
    (TokenKind::Whitespace, Some(" ")),
    (TokenKind::Identifier, Some("f")),
    (TokenKind::FormatStringStart, Some("'''{{")),
    (TokenKind::StringToken, Some("'foo'")),
    (TokenKind::FormatStringContinue, Some("}}{{")),
    (TokenKind::StringToken, Some("'bar'")),
    (TokenKind::FormatStringEnd, Some("}}'''")),
    (TokenKind::Eol, Some("\n")),
    (TokenKind::Identifier, Some("bar")),
    (TokenKind::Colon, None),
  ])
}

///|
test "upstream lexer::tests::indented_line" {
  assert_upstream_tokens("foo:\n a", [
    (TokenKind::Identifier, Some("foo")),
    (TokenKind::Colon, None),
    (TokenKind::Eol, None),
    (TokenKind::Indent, Some(" ")),
    (TokenKind::Text, Some("a")),
    (TokenKind::Dedent, None),
  ])
}

///|
test "upstream lexer::tests::indented_line_containing_unpaired_carriage_return" {
  assert_upstream_tokens("foo:\n \r \n", [
    (TokenKind::Identifier, Some("foo")),
    (TokenKind::Colon, None),
    (TokenKind::Eol, None),
    (TokenKind::Indent, Some(" ")),
    (TokenKind::Text, Some("\r ")),
    (TokenKind::Eol, None),
    (TokenKind::Dedent, None),
  ])
}

///|
test "upstream lexer::tests::indented_normal_nonempty_blank" {
  assert_upstream_tokens("a\n  b\n\t\t\n  c\n", [
    (TokenKind::Identifier, Some("a")),
    (TokenKind::Eol, None),
    (TokenKind::Indent, Some("  ")),
    (TokenKind::Identifier, Some("b")),
    (TokenKind::Eol, None),
    (TokenKind::Whitespace, Some("\t\t")),
    (TokenKind::Eol, None),
    (TokenKind::Whitespace, Some("  ")),
    (TokenKind::Identifier, Some("c")),
    (TokenKind::Eol, None),
    (TokenKind::Dedent, None),
  ])
}

///|
test "upstream lexer::tests::interpolation_empty" {
  assert_upstream_tokens("hello:\n echo {{}}", [
    (TokenKind::Identifier, Some("hello")),
    (TokenKind::Colon, None),
    (TokenKind::Eol, None),
    (TokenKind::Indent, Some(" ")),
    (TokenKind::Text, Some("echo ")),
    (TokenKind::InterpolationStart, None),
    (TokenKind::InterpolationEnd, None),
    (TokenKind::Dedent, None),
  ])
}

///|
test "upstream lexer::tests::interpolation_expression" {
  assert_upstream_tokens("hello:\n echo {{`echo hello` + `echo goodbye`}}", [
    (TokenKind::Identifier, Some("hello")),
    (TokenKind::Colon, None),
    (TokenKind::Eol, None),
    (TokenKind::Indent, Some(" ")),
    (TokenKind::Text, Some("echo ")),
    (TokenKind::InterpolationStart, None),
    (TokenKind::Backtick, Some("`echo hello`")),
    (TokenKind::Whitespace, None),
    (TokenKind::Plus, None),
    (TokenKind::Whitespace, None),
    (TokenKind::Backtick, Some("`echo goodbye`")),
    (TokenKind::InterpolationEnd, None),
    (TokenKind::Dedent, None),
  ])
}

///|
test "upstream lexer::tests::interpolation_raw_multiline_string" {
  assert_upstream_tokens("hello:\n echo {{'\n'}}", [
    (TokenKind::Identifier, Some("hello")),
    (TokenKind::Colon, None),
    (TokenKind::Eol, None),
    (TokenKind::Indent, Some(" ")),
    (TokenKind::Text, Some("echo ")),
    (TokenKind::InterpolationStart, None),
    (TokenKind::StringToken, Some("'\n'")),
    (TokenKind::InterpolationEnd, None),
    (TokenKind::Dedent, None),
  ])
}

///|
test "upstream lexer::tests::open_delimiter_eol" {
  assert_upstream_tokens("[\n](\n){\n}", [
    (TokenKind::BracketL, None),
    (TokenKind::Whitespace, Some("\n")),
    (TokenKind::BracketR, None),
    (TokenKind::ParenL, None),
    (TokenKind::Whitespace, Some("\n")),
    (TokenKind::ParenR, None),
    (TokenKind::BraceL, None),
    (TokenKind::Whitespace, Some("\n")),
    (TokenKind::BraceR, None),
  ])
}

///|
test "upstream lexer::tests::raw_string" {
  assert_upstream_tokens("'hello'", [(TokenKind::StringToken, Some("'hello'"))])
}

///|
test "upstream lexer::tests::raw_string_multi_line" {
  assert_upstream_tokens("'hello\ngoodbye'", [
    (TokenKind::StringToken, Some("'hello\ngoodbye'")),
  ])
}

///|
test "upstream lexer::tests::tokenize_assignment_backticks" {
  assert_upstream_tokens("a = `echo hello` + `echo goodbye`", [
    (TokenKind::Identifier, Some("a")),
    (TokenKind::Whitespace, None),
    (TokenKind::Equals, None),
    (TokenKind::Whitespace, None),
    (TokenKind::Backtick, Some("`echo hello`")),
    (TokenKind::Whitespace, None),
    (TokenKind::Plus, None),
    (TokenKind::Whitespace, None),
    (TokenKind::Backtick, Some("`echo goodbye`")),
  ])
}

///|
test "upstream lexer::tests::tokenize_comment" {
  assert_upstream_tokens("a:=#", [
    (TokenKind::Identifier, Some("a")),
    (TokenKind::ColonEquals, None),
    (TokenKind::Comment, Some("#")),
  ])
}

///|
test "upstream lexer::tests::tokenize_comment_with_bang" {
  assert_upstream_tokens("a:=#foo!", [
    (TokenKind::Identifier, Some("a")),
    (TokenKind::ColonEquals, None),
    (TokenKind::Comment, Some("#foo!")),
  ])
}

///|
test "upstream lexer::tests::tokenize_empty_interpolation" {
  assert_upstream_tokens("hello:\n echo {{}}", [
    (TokenKind::Identifier, Some("hello")),
    (TokenKind::Colon, None),
    (TokenKind::Eol, None),
    (TokenKind::Indent, Some(" ")),
    (TokenKind::Text, Some("echo ")),
    (TokenKind::InterpolationStart, None),
    (TokenKind::InterpolationEnd, None),
    (TokenKind::Dedent, None),
  ])
}

///|
test "upstream lexer::tests::tokenize_indented_line" {
  assert_upstream_tokens("foo:\n a", [
    (TokenKind::Identifier, Some("foo")),
    (TokenKind::Colon, None),
    (TokenKind::Eol, None),
    (TokenKind::Indent, Some(" ")),
    (TokenKind::Text, Some("a")),
    (TokenKind::Dedent, None),
  ])
}

///|
test "upstream lexer::tests::tokenize_interpolation_backticks" {
  assert_upstream_tokens("hello:\n echo {{`echo hello` + `echo goodbye`}}", [
    (TokenKind::Identifier, Some("hello")),
    (TokenKind::Colon, None),
    (TokenKind::Eol, None),
    (TokenKind::Indent, Some(" ")),
    (TokenKind::Text, Some("echo ")),
    (TokenKind::InterpolationStart, None),
    (TokenKind::Backtick, Some("`echo hello`")),
    (TokenKind::Whitespace, None),
    (TokenKind::Plus, None),
    (TokenKind::Whitespace, None),
    (TokenKind::Backtick, Some("`echo goodbye`")),
    (TokenKind::InterpolationEnd, None),
    (TokenKind::Dedent, None),
  ])
}

///|
test "upstream lexer::tests::tokenize_parens" {
  assert_upstream_tokens("((())) ()abc(+", [
    (TokenKind::ParenL, None),
    (TokenKind::ParenL, None),
    (TokenKind::ParenL, None),
    (TokenKind::ParenR, None),
    (TokenKind::ParenR, None),
    (TokenKind::ParenR, None),
    (TokenKind::Whitespace, None),
    (TokenKind::ParenL, None),
    (TokenKind::ParenR, None),
    (TokenKind::Identifier, Some("abc")),
    (TokenKind::ParenL, None),
    (TokenKind::Plus, None),
  ])
}

///|
test "upstream lexer::tests::tokenize_recipe_after_body" {
  assert_upstream_tokens("foo:\n echo FOO\n\nfoo:", [
    (TokenKind::Identifier, Some("foo")),
    (TokenKind::Colon, None),
    (TokenKind::Eol, None),
    (TokenKind::Indent, Some(" ")),
    (TokenKind::Text, Some("echo FOO")),
    (TokenKind::Eol, None),
    (TokenKind::Dedent, None),
    (TokenKind::Eol, None),
    (TokenKind::Identifier, Some("foo")),
    (TokenKind::Colon, None),
  ])
}

///|
test "upstream lexer::tests::tokenize_recipe_complex_interpolation_expression" {
  assert_upstream_tokens("foo: #lol\n {{a + b + \"z\" + blarg}}", [
    (TokenKind::Identifier, Some("foo")),
    (TokenKind::Colon, None),
    (TokenKind::Whitespace, Some(" ")),
    (TokenKind::Comment, Some("#lol")),
    (TokenKind::Eol, None),
    (TokenKind::Indent, Some(" ")),
    (TokenKind::InterpolationStart, None),
    (TokenKind::Identifier, Some("a")),
    (TokenKind::Whitespace, None),
    (TokenKind::Plus, None),
    (TokenKind::Whitespace, None),
    (TokenKind::Identifier, Some("b")),
    (TokenKind::Whitespace, None),
    (TokenKind::Plus, None),
    (TokenKind::Whitespace, None),
    (TokenKind::StringToken, Some("\"z\"")),
    (TokenKind::Whitespace, None),
    (TokenKind::Plus, None),
    (TokenKind::Whitespace, None),
    (TokenKind::Identifier, Some("blarg")),
    (TokenKind::InterpolationEnd, None),
    (TokenKind::Dedent, None),
  ])
}

///|
test "upstream lexer::tests::tokenize_recipe_interpolation_eof" {
  assert_upstream_tokens(
    "foo: # more comments\n {{hello}}\n# another comment\n",
    [
      (TokenKind::Identifier, Some("foo")),
      (TokenKind::Colon, None),
      (TokenKind::Whitespace, None),
      (TokenKind::Comment, Some("# more comments")),
      (TokenKind::Eol, None),
      (TokenKind::Indent, Some(" ")),
      (TokenKind::InterpolationStart, None),
      (TokenKind::Identifier, Some("hello")),
      (TokenKind::InterpolationEnd, None),
      (TokenKind::Eol, None),
      (TokenKind::Dedent, None),
      (TokenKind::Comment, Some("# another comment")),
      (TokenKind::Eol, None),
    ],
  )
}

///|
test "upstream lexer::tests::tokenize_recipe_multiple_interpolations" {
  assert_upstream_tokens("foo:,#ok\n {{a}}0{{b}}1{{c}}", [
    (TokenKind::Identifier, Some("foo")),
    (TokenKind::Colon, None),
    (TokenKind::Comma, None),
    (TokenKind::Comment, Some("#ok")),
    (TokenKind::Eol, None),
    (TokenKind::Indent, Some(" ")),
    (TokenKind::InterpolationStart, None),
    (TokenKind::Identifier, Some("a")),
    (TokenKind::InterpolationEnd, None),
    (TokenKind::Text, Some("0")),
    (TokenKind::InterpolationStart, None),
    (TokenKind::Identifier, Some("b")),
    (TokenKind::InterpolationEnd, None),
    (TokenKind::Text, Some("1")),
    (TokenKind::InterpolationStart, None),
    (TokenKind::Identifier, Some("c")),
    (TokenKind::InterpolationEnd, None),
    (TokenKind::Dedent, None),
  ])
}

///|
test "upstream lexer::tests::tokenize_strings" {
  assert_upstream_tokens(
    "a = \"'a'\" + '\"b\"' + \"'c'\" + '\"d\"'#echo hello",
    [
      (TokenKind::Identifier, Some("a")),
      (TokenKind::Whitespace, None),
      (TokenKind::Equals, None),
      (TokenKind::Whitespace, None),
      (TokenKind::StringToken, Some("\"'a'\"")),
      (TokenKind::Whitespace, None),
      (TokenKind::Plus, None),
      (TokenKind::Whitespace, None),
      (TokenKind::StringToken, Some("'\"b\"'")),
      (TokenKind::Whitespace, None),
      (TokenKind::Plus, None),
      (TokenKind::Whitespace, None),
      (TokenKind::StringToken, Some("\"'c'\"")),
      (TokenKind::Whitespace, None),
      (TokenKind::Plus, None),
      (TokenKind::Whitespace, None),
      (TokenKind::StringToken, Some("'\"d\"'")),
      (TokenKind::Comment, Some("#echo hello")),
    ],
  )
}
