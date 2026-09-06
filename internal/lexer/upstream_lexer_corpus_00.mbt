///|
test "upstream lexer::tests::ampersand_ampersand" {
  assert_upstream_tokens("&&", [(AmpersandAmpersand, None)])
}

///|
test "upstream lexer::tests::backtick" {
  assert_upstream_tokens("`echo`", [(Backtick, Some("`echo`"))])
}

///|
test "upstream lexer::tests::backtick_multi_line" {
  assert_upstream_tokens("`echo\necho`", [(Backtick, Some("`echo\necho`"))])
}

///|
test "upstream lexer::tests::bang" {
  assert_upstream_tokens("!", [(Bang, None)])
}

///|
test "upstream lexer::tests::bang_equals" {
  assert_upstream_tokens("!=", [(BangEquals, None)])
}

///|
test "upstream lexer::tests::brace_l" {
  assert_upstream_tokens("{", [(BraceL, None)])
}

///|
test "upstream lexer::tests::brace_lll" {
  assert_upstream_tokens("{{{", [(BraceL, None), (BraceL, None), (BraceL, None)])
}

///|
test "upstream lexer::tests::brace_r" {
  assert_upstream_tokens("{}", [(BraceL, None), (BraceR, None)])
}

///|
test "upstream lexer::tests::brace_rrr" {
  assert_upstream_tokens("{{{}}}", [
    (BraceL, None),
    (BraceL, None),
    (BraceL, None),
    (BraceR, None),
    (BraceR, None),
    (BraceR, None),
  ])
}

///|
test "upstream lexer::tests::brackets" {
  assert_upstream_tokens("[][]", [
    (BracketL, None),
    (BracketR, None),
    (BracketL, None),
    (BracketR, None),
  ])
}

///|
test "upstream lexer::tests::cooked_multiline_string" {
  assert_upstream_tokens("\"\"\"hello\ngoodbye\"\"\"", [
    (StringToken, Some("\"\"\"hello\ngoodbye\"\"\"")),
  ])
}

///|
test "upstream lexer::tests::cooked_string" {
  assert_upstream_tokens("\"hello\"", [(StringToken, Some("\"hello\""))])
}

///|
test "upstream lexer::tests::cooked_string_multi_line" {
  assert_upstream_tokens("\"hello\ngoodbye\"", [
    (StringToken, Some("\"hello\ngoodbye\"")),
  ])
}

///|
test "upstream lexer::tests::crlf_newline" {
  assert_upstream_tokens("#\r\n#asdf\r\n", [
    (Comment, Some("#")),
    (Eol, Some("\r\n")),
    (Comment, Some("#asdf")),
    (Eol, Some("\r\n")),
  ])
}

///|
test "upstream lexer::tests::dollar" {
  assert_upstream_tokens("$", [(Dollar, None)])
}

///|
test "upstream lexer::tests::eol_carriage_return_linefeed" {
  assert_upstream_tokens("\r\n", [(Eol, Some("\r\n"))])
}

///|
test "upstream lexer::tests::eol_linefeed" {
  assert_upstream_tokens("\n", [(Eol, None)])
}

///|
test "upstream lexer::tests::export_complex" {
  assert_upstream_tokens("export foo = ('foo' + 'bar') + `baz`", [
    (Identifier, Some("export")),
    (Whitespace, None),
    (Identifier, Some("foo")),
    (Whitespace, None),
    (Equals, None),
    (Whitespace, None),
    (ParenL, None),
    (StringToken, Some("'foo'")),
    (Whitespace, None),
    (Plus, None),
    (Whitespace, None),
    (StringToken, Some("'bar'")),
    (ParenR, None),
    (Whitespace, None),
    (Plus, None),
    (Whitespace, None),
    (Backtick, Some("`baz`")),
  ])
}

///|
test "upstream lexer::tests::export_concatenation" {
  assert_upstream_tokens("export foo = 'foo' + 'bar'", [
    (Identifier, Some("export")),
    (Whitespace, None),
    (Identifier, Some("foo")),
    (Whitespace, None),
    (Equals, None),
    (Whitespace, None),
    (StringToken, Some("'foo'")),
    (Whitespace, None),
    (Plus, None),
    (Whitespace, None),
    (StringToken, Some("'bar'")),
  ])
}

///|
test "upstream lexer::tests::format_string_continue" {
  assert_upstream_tokens("f'{{foo}}bar{{baz}}'", [
    (Identifier, Some("f")),
    (FormatStringStart, Some("'{{")),
    (Identifier, Some("foo")),
    (FormatStringContinue, Some("}}bar{{")),
    (Identifier, Some("baz")),
    (FormatStringEnd, Some("}}'")),
  ])
}

///|
test "upstream lexer::tests::format_string_empty" {
  assert_upstream_tokens("f''", [
    (Identifier, Some("f")),
    (StringToken, Some("''")),
  ])
}

///|
test "upstream lexer::tests::format_string_followed_by_recipe" {
  assert_upstream_tokens("foo := f'{{'foo'}}{{'bar'}}'\nbar:", [
    (Identifier, Some("foo")),
    (Whitespace, Some(" ")),
    (ColonEquals, Some(":=")),
    (Whitespace, Some(" ")),
    (Identifier, Some("f")),
    (FormatStringStart, Some("'{{")),
    (StringToken, Some("'foo'")),
    (FormatStringContinue, Some("}}{{")),
    (StringToken, Some("'bar'")),
    (FormatStringEnd, Some("}}'")),
    (Eol, Some("\n")),
    (Identifier, Some("bar")),
    (Colon, None),
  ])
}

///|
test "upstream lexer::tests::format_string_identifier" {
  assert_upstream_tokens("f'{{foo}}'", [
    (Identifier, Some("f")),
    (FormatStringStart, Some("'{{")),
    (Identifier, Some("foo")),
    (FormatStringEnd, Some("}}'")),
  ])
}

///|
test "upstream lexer::tests::format_string_whitespace" {
  assert_upstream_tokens("f '{{foo}}'", [
    (Identifier, Some("f")),
    (Whitespace, None),
    (StringToken, Some("'{{foo}}'")),
  ])
}
