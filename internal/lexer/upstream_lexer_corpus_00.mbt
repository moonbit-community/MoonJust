///|
test "upstream lexer::tests::ampersand_ampersand" {
  assert_upstream_tokens("&&", [(TokenKind::AmpersandAmpersand, None)])
}

///|
test "upstream lexer::tests::backtick" {
  assert_upstream_tokens("`echo`", [(TokenKind::Backtick, Some("`echo`"))])
}

///|
test "upstream lexer::tests::backtick_multi_line" {
  assert_upstream_tokens("`echo\necho`", [
    (TokenKind::Backtick, Some("`echo\necho`")),
  ])
}

///|
test "upstream lexer::tests::bang" {
  assert_upstream_tokens("!", [(TokenKind::Bang, None)])
}

///|
test "upstream lexer::tests::bang_equals" {
  assert_upstream_tokens("!=", [(TokenKind::BangEquals, None)])
}

///|
test "upstream lexer::tests::brace_l" {
  assert_upstream_tokens("{", [(TokenKind::BraceL, None)])
}

///|
test "upstream lexer::tests::brace_lll" {
  assert_upstream_tokens("{{{", [
    (TokenKind::BraceL, None),
    (TokenKind::BraceL, None),
    (TokenKind::BraceL, None),
  ])
}

///|
test "upstream lexer::tests::brace_r" {
  assert_upstream_tokens("{}", [
    (TokenKind::BraceL, None),
    (TokenKind::BraceR, None),
  ])
}

///|
test "upstream lexer::tests::brace_rrr" {
  assert_upstream_tokens("{{{}}}", [
    (TokenKind::BraceL, None),
    (TokenKind::BraceL, None),
    (TokenKind::BraceL, None),
    (TokenKind::BraceR, None),
    (TokenKind::BraceR, None),
    (TokenKind::BraceR, None),
  ])
}

///|
test "upstream lexer::tests::brackets" {
  assert_upstream_tokens("[][]", [
    (TokenKind::BracketL, None),
    (TokenKind::BracketR, None),
    (TokenKind::BracketL, None),
    (TokenKind::BracketR, None),
  ])
}

///|
test "upstream lexer::tests::cooked_multiline_string" {
  assert_upstream_tokens("\"\"\"hello\ngoodbye\"\"\"", [
    (TokenKind::StringToken, Some("\"\"\"hello\ngoodbye\"\"\"")),
  ])
}

///|
test "upstream lexer::tests::cooked_string" {
  assert_upstream_tokens("\"hello\"", [
    (TokenKind::StringToken, Some("\"hello\"")),
  ])
}

///|
test "upstream lexer::tests::cooked_string_multi_line" {
  assert_upstream_tokens("\"hello\ngoodbye\"", [
    (TokenKind::StringToken, Some("\"hello\ngoodbye\"")),
  ])
}

///|
test "upstream lexer::tests::crlf_newline" {
  assert_upstream_tokens("#\r\n#asdf\r\n", [
    (TokenKind::Comment, Some("#")),
    (TokenKind::Eol, Some("\r\n")),
    (TokenKind::Comment, Some("#asdf")),
    (TokenKind::Eol, Some("\r\n")),
  ])
}

///|
test "upstream lexer::tests::dollar" {
  assert_upstream_tokens("$", [(TokenKind::Dollar, None)])
}

///|
test "upstream lexer::tests::eol_carriage_return_linefeed" {
  assert_upstream_tokens("\r\n", [(TokenKind::Eol, Some("\r\n"))])
}

///|
test "upstream lexer::tests::eol_linefeed" {
  assert_upstream_tokens("\n", [(TokenKind::Eol, None)])
}

///|
test "upstream lexer::tests::export_complex" {
  assert_upstream_tokens("export foo = ('foo' + 'bar') + `baz`", [
    (TokenKind::Identifier, Some("export")),
    (TokenKind::Whitespace, None),
    (TokenKind::Identifier, Some("foo")),
    (TokenKind::Whitespace, None),
    (TokenKind::Equals, None),
    (TokenKind::Whitespace, None),
    (TokenKind::ParenL, None),
    (TokenKind::StringToken, Some("'foo'")),
    (TokenKind::Whitespace, None),
    (TokenKind::Plus, None),
    (TokenKind::Whitespace, None),
    (TokenKind::StringToken, Some("'bar'")),
    (TokenKind::ParenR, None),
    (TokenKind::Whitespace, None),
    (TokenKind::Plus, None),
    (TokenKind::Whitespace, None),
    (TokenKind::Backtick, Some("`baz`")),
  ])
}

///|
test "upstream lexer::tests::export_concatenation" {
  assert_upstream_tokens("export foo = 'foo' + 'bar'", [
    (TokenKind::Identifier, Some("export")),
    (TokenKind::Whitespace, None),
    (TokenKind::Identifier, Some("foo")),
    (TokenKind::Whitespace, None),
    (TokenKind::Equals, None),
    (TokenKind::Whitespace, None),
    (TokenKind::StringToken, Some("'foo'")),
    (TokenKind::Whitespace, None),
    (TokenKind::Plus, None),
    (TokenKind::Whitespace, None),
    (TokenKind::StringToken, Some("'bar'")),
  ])
}

///|
test "upstream lexer::tests::format_string_continue" {
  assert_upstream_tokens("f'{{foo}}bar{{baz}}'", [
    (TokenKind::Identifier, Some("f")),
    (TokenKind::FormatStringStart, Some("'{{")),
    (TokenKind::Identifier, Some("foo")),
    (TokenKind::FormatStringContinue, Some("}}bar{{")),
    (TokenKind::Identifier, Some("baz")),
    (TokenKind::FormatStringEnd, Some("}}'")),
  ])
}

///|
test "upstream lexer::tests::format_string_empty" {
  assert_upstream_tokens("f''", [
    (TokenKind::Identifier, Some("f")),
    (TokenKind::StringToken, Some("''")),
  ])
}

///|
test "upstream lexer::tests::format_string_followed_by_recipe" {
  assert_upstream_tokens("foo := f'{{'foo'}}{{'bar'}}'\nbar:", [
    (TokenKind::Identifier, Some("foo")),
    (TokenKind::Whitespace, Some(" ")),
    (TokenKind::ColonEquals, Some(":=")),
    (TokenKind::Whitespace, Some(" ")),
    (TokenKind::Identifier, Some("f")),
    (TokenKind::FormatStringStart, Some("'{{")),
    (TokenKind::StringToken, Some("'foo'")),
    (TokenKind::FormatStringContinue, Some("}}{{")),
    (TokenKind::StringToken, Some("'bar'")),
    (TokenKind::FormatStringEnd, Some("}}'")),
    (TokenKind::Eol, Some("\n")),
    (TokenKind::Identifier, Some("bar")),
    (TokenKind::Colon, None),
  ])
}

///|
test "upstream lexer::tests::format_string_identifier" {
  assert_upstream_tokens("f'{{foo}}'", [
    (TokenKind::Identifier, Some("f")),
    (TokenKind::FormatStringStart, Some("'{{")),
    (TokenKind::Identifier, Some("foo")),
    (TokenKind::FormatStringEnd, Some("}}'")),
  ])
}

///|
test "upstream lexer::tests::format_string_whitespace" {
  assert_upstream_tokens("f '{{foo}}'", [
    (TokenKind::Identifier, Some("f")),
    (TokenKind::Whitespace, None),
    (TokenKind::StringToken, Some("'{{foo}}'")),
  ])
}
