///|
test "upstream lexer::tests::format_string_wrong_identifier" {
  assert_upstream_tokens("g'{{foo}}'", [
    (Identifier, Some("g")),
    (StringToken, Some("'{{foo}}'")),
  ])
}

///|
test "upstream lexer::tests::indented_format_string_followed_by_recipe" {
  assert_upstream_tokens("foo := f'''{{'foo'}}{{'bar'}}'''\nbar:", [
    (Identifier, Some("foo")),
    (Whitespace, Some(" ")),
    (ColonEquals, Some(":=")),
    (Whitespace, Some(" ")),
    (Identifier, Some("f")),
    (FormatStringStart, Some("'''{{")),
    (StringToken, Some("'foo'")),
    (FormatStringContinue, Some("}}{{")),
    (StringToken, Some("'bar'")),
    (FormatStringEnd, Some("}}'''")),
    (Eol, Some("\n")),
    (Identifier, Some("bar")),
    (Colon, None),
  ])
}

///|
test "upstream lexer::tests::indented_line" {
  assert_upstream_tokens("foo:\n a", [
    (Identifier, Some("foo")),
    (Colon, None),
    (Eol, None),
    (Indent, Some(" ")),
    (Text, Some("a")),
    (Dedent, None),
  ])
}

///|
test "upstream lexer::tests::indented_line_containing_unpaired_carriage_return" {
  assert_upstream_tokens("foo:\n \r \n", [
    (Identifier, Some("foo")),
    (Colon, None),
    (Eol, None),
    (Indent, Some(" ")),
    (Text, Some("\r ")),
    (Eol, None),
    (Dedent, None),
  ])
}

///|
test "upstream lexer::tests::indented_normal_nonempty_blank" {
  assert_upstream_tokens("a\n  b\n\t\t\n  c\n", [
    (Identifier, Some("a")),
    (Eol, None),
    (Indent, Some("  ")),
    (Identifier, Some("b")),
    (Eol, None),
    (Whitespace, Some("\t\t")),
    (Eol, None),
    (Whitespace, Some("  ")),
    (Identifier, Some("c")),
    (Eol, None),
    (Dedent, None),
  ])
}

///|
test "upstream lexer::tests::interpolation_empty" {
  assert_upstream_tokens("hello:\n echo {{}}", [
    (Identifier, Some("hello")),
    (Colon, None),
    (Eol, None),
    (Indent, Some(" ")),
    (Text, Some("echo ")),
    (InterpolationStart, None),
    (InterpolationEnd, None),
    (Dedent, None),
  ])
}

///|
test "upstream lexer::tests::interpolation_expression" {
  assert_upstream_tokens("hello:\n echo {{`echo hello` + `echo goodbye`}}", [
    (Identifier, Some("hello")),
    (Colon, None),
    (Eol, None),
    (Indent, Some(" ")),
    (Text, Some("echo ")),
    (InterpolationStart, None),
    (Backtick, Some("`echo hello`")),
    (Whitespace, None),
    (Plus, None),
    (Whitespace, None),
    (Backtick, Some("`echo goodbye`")),
    (InterpolationEnd, None),
    (Dedent, None),
  ])
}

///|
test "upstream lexer::tests::interpolation_raw_multiline_string" {
  assert_upstream_tokens("hello:\n echo {{'\n'}}", [
    (Identifier, Some("hello")),
    (Colon, None),
    (Eol, None),
    (Indent, Some(" ")),
    (Text, Some("echo ")),
    (InterpolationStart, None),
    (StringToken, Some("'\n'")),
    (InterpolationEnd, None),
    (Dedent, None),
  ])
}

///|
test "upstream lexer::tests::open_delimiter_eol" {
  assert_upstream_tokens("[\n](\n){\n}", [
    (BracketL, None),
    (Whitespace, Some("\n")),
    (BracketR, None),
    (ParenL, None),
    (Whitespace, Some("\n")),
    (ParenR, None),
    (BraceL, None),
    (Whitespace, Some("\n")),
    (BraceR, None),
  ])
}

///|
test "upstream lexer::tests::raw_string" {
  assert_upstream_tokens("'hello'", [(StringToken, Some("'hello'"))])
}

///|
test "upstream lexer::tests::raw_string_multi_line" {
  assert_upstream_tokens("'hello\ngoodbye'", [
    (StringToken, Some("'hello\ngoodbye'")),
  ])
}

///|
test "upstream lexer::tests::tokenize_assignment_backticks" {
  assert_upstream_tokens("a = `echo hello` + `echo goodbye`", [
    (Identifier, Some("a")),
    (Whitespace, None),
    (Equals, None),
    (Whitespace, None),
    (Backtick, Some("`echo hello`")),
    (Whitespace, None),
    (Plus, None),
    (Whitespace, None),
    (Backtick, Some("`echo goodbye`")),
  ])
}

///|
test "upstream lexer::tests::tokenize_comment" {
  assert_upstream_tokens("a:=#", [
    (Identifier, Some("a")),
    (ColonEquals, None),
    (Comment, Some("#")),
  ])
}

///|
test "upstream lexer::tests::tokenize_comment_with_bang" {
  assert_upstream_tokens("a:=#foo!", [
    (Identifier, Some("a")),
    (ColonEquals, None),
    (Comment, Some("#foo!")),
  ])
}

///|
test "upstream lexer::tests::tokenize_empty_interpolation" {
  assert_upstream_tokens("hello:\n echo {{}}", [
    (Identifier, Some("hello")),
    (Colon, None),
    (Eol, None),
    (Indent, Some(" ")),
    (Text, Some("echo ")),
    (InterpolationStart, None),
    (InterpolationEnd, None),
    (Dedent, None),
  ])
}

///|
test "upstream lexer::tests::tokenize_indented_line" {
  assert_upstream_tokens("foo:\n a", [
    (Identifier, Some("foo")),
    (Colon, None),
    (Eol, None),
    (Indent, Some(" ")),
    (Text, Some("a")),
    (Dedent, None),
  ])
}

///|
test "upstream lexer::tests::tokenize_interpolation_backticks" {
  assert_upstream_tokens("hello:\n echo {{`echo hello` + `echo goodbye`}}", [
    (Identifier, Some("hello")),
    (Colon, None),
    (Eol, None),
    (Indent, Some(" ")),
    (Text, Some("echo ")),
    (InterpolationStart, None),
    (Backtick, Some("`echo hello`")),
    (Whitespace, None),
    (Plus, None),
    (Whitespace, None),
    (Backtick, Some("`echo goodbye`")),
    (InterpolationEnd, None),
    (Dedent, None),
  ])
}

///|
test "upstream lexer::tests::tokenize_parens" {
  assert_upstream_tokens("((())) ()abc(+", [
    (ParenL, None),
    (ParenL, None),
    (ParenL, None),
    (ParenR, None),
    (ParenR, None),
    (ParenR, None),
    (Whitespace, None),
    (ParenL, None),
    (ParenR, None),
    (Identifier, Some("abc")),
    (ParenL, None),
    (Plus, None),
  ])
}

///|
test "upstream lexer::tests::tokenize_recipe_after_body" {
  assert_upstream_tokens("foo:\n echo FOO\n\nfoo:", [
    (Identifier, Some("foo")),
    (Colon, None),
    (Eol, None),
    (Indent, Some(" ")),
    (Text, Some("echo FOO")),
    (Eol, None),
    (Dedent, None),
    (Eol, None),
    (Identifier, Some("foo")),
    (Colon, None),
  ])
}

///|
test "upstream lexer::tests::tokenize_recipe_complex_interpolation_expression" {
  assert_upstream_tokens("foo: #lol\n {{a + b + \"z\" + blarg}}", [
    (Identifier, Some("foo")),
    (Colon, None),
    (Whitespace, Some(" ")),
    (Comment, Some("#lol")),
    (Eol, None),
    (Indent, Some(" ")),
    (InterpolationStart, None),
    (Identifier, Some("a")),
    (Whitespace, None),
    (Plus, None),
    (Whitespace, None),
    (Identifier, Some("b")),
    (Whitespace, None),
    (Plus, None),
    (Whitespace, None),
    (StringToken, Some("\"z\"")),
    (Whitespace, None),
    (Plus, None),
    (Whitespace, None),
    (Identifier, Some("blarg")),
    (InterpolationEnd, None),
    (Dedent, None),
  ])
}

///|
test "upstream lexer::tests::tokenize_recipe_interpolation_eof" {
  assert_upstream_tokens(
    "foo: # more comments\n {{hello}}\n# another comment\n",
    [
      (Identifier, Some("foo")),
      (Colon, None),
      (Whitespace, None),
      (Comment, Some("# more comments")),
      (Eol, None),
      (Indent, Some(" ")),
      (InterpolationStart, None),
      (Identifier, Some("hello")),
      (InterpolationEnd, None),
      (Eol, None),
      (Dedent, None),
      (Comment, Some("# another comment")),
      (Eol, None),
    ],
  )
}

///|
test "upstream lexer::tests::tokenize_recipe_multiple_interpolations" {
  assert_upstream_tokens("foo:,#ok\n {{a}}0{{b}}1{{c}}", [
    (Identifier, Some("foo")),
    (Colon, None),
    (Comma, None),
    (Comment, Some("#ok")),
    (Eol, None),
    (Indent, Some(" ")),
    (InterpolationStart, None),
    (Identifier, Some("a")),
    (InterpolationEnd, None),
    (Text, Some("0")),
    (InterpolationStart, None),
    (Identifier, Some("b")),
    (InterpolationEnd, None),
    (Text, Some("1")),
    (InterpolationStart, None),
    (Identifier, Some("c")),
    (InterpolationEnd, None),
    (Dedent, None),
  ])
}

///|
test "upstream lexer::tests::tokenize_strings" {
  assert_upstream_tokens(
    "a = \"'a'\" + '\"b\"' + \"'c'\" + '\"d\"'#echo hello",
    [
      (Identifier, Some("a")),
      (Whitespace, None),
      (Equals, None),
      (Whitespace, None),
      (StringToken, Some("\"'a'\"")),
      (Whitespace, None),
      (Plus, None),
      (Whitespace, None),
      (StringToken, Some("'\"b\"'")),
      (Whitespace, None),
      (Plus, None),
      (Whitespace, None),
      (StringToken, Some("\"'c'\"")),
      (Whitespace, None),
      (Plus, None),
      (Whitespace, None),
      (StringToken, Some("'\"d\"'")),
      (Comment, Some("#echo hello")),
    ],
  )
}
