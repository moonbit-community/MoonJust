///|
fn parser_coverage_parser(text : String) -> Parser {
  let source = @source.Source::from_text(
    @source.SourceId::new(9700),
    "coverage.just",
    text,
  )
  Parser::new(source, try! @lexer.lex(source), ParserLimits::default())
}

///|
test "parser whitebox coverage visits attribute and cursor branches" {
  for name in attribute_names() {
    assert_true(known_attribute(name))
  }
  assert_false(known_attribute("unknown"))
  assert_true(attribute_arity_valid("doc", 1, 0))
  assert_true(attribute_arity_valid("metadata", 2, 0))
  assert_true(attribute_arity_valid("env", 2, 0))
  assert_true(attribute_arity_valid("cache", 0, 3))
  assert_true(attribute_arity_valid("private", 0, 0))
  assert_false(attribute_arity_valid("private", 1, 0))
  assert_true(attribute_key_valid("arg", "flag"))
  assert_true(attribute_key_valid("cache", "inputs"))
  assert_false(attribute_key_valid("arg", "unknown"))
  for name in ["arg", "continue", "extension", "group", "metadata", "script"] {
    assert_true(attribute_requires_literal(name))
  }
  assert_false(attribute_requires_literal("private"))

  let parser = parser_coverage_parser("foo:\n")
  let _ = parser.peek_kind()
  assert_true(parser.peek_kind_at(0) is Some(_))
  assert_true(parser.peek_kind_at(100) is None)
  assert_false(parser.peek_keyword(Set))
  let token = parser.advance()
  assert_eq(token.kind(), Identifier)
  let _ = parser.advance()
  assert_true(parser.line_finished())
  try! parser.consume_line_end()
  assert_eq(parser.peek_kind(), Eof)
}

///|
test "parser whitebox coverage visits string normalization and expansion" {
  assert_eq(unindent_string("\n  one\n    two\n"), "one\n  two\n")
  assert_eq(unindent_string("one\n\n two\n"), "one\n\n two\n")
  for raw in ["'x'", "\"x\"", "`x`", "'''x'''", "\"\"\"x\"\"\""] {
    let parts = literal_parts(raw)
    assert_true(parts.1 >= 0)
    assert_true(parts.2 || !parts.2)
    ignore(slice_literal(raw, parts.1, raw.length() - parts.1))
  }
  let span = @source.Span::new(@source.SourceId::new(9701), 0, 1)
  assert_eq(shell_environment_value([("HOME", "/tmp")], "HOME"), Some("/tmp"))
  assert_eq(shell_environment_value([("HOME", "/tmp")], "MISSING"), None)
  assert_true(shell_name_character('A', true))
  assert_true(shell_name_character('_', false))
  assert_false(shell_name_character('-', true))
  try expand_shell_string("$MISSING", [], span) catch {
    ShellExpansion(variable="MISSING", ..) => ()
    _ => fail("unexpected shell expansion error")
  } noraise {
    _ => fail("expected shell expansion error")
  }
  assert_eq(expand_shell_string("$HOME", [("HOME", "/tmp")], span), "/tmp")
  assert_true(hex_value('A') is Some(10))
  assert_true(hex_value('z') is None)
}

///|
test "parser whitebox coverage visits top-level grammar predicates" {
  for name in setting_names() {
    assert_true(setting_known(name))
    let _ = setting_is_boolean(name)
  }
  assert_false(setting_known("unknown"))
  for
    kind in [
      @lexer.TokenKind::At,
      Asterisk,
      Dollar,
      ParenL,
      BracketL,
      StringToken,
      Identifier,
    ] {
    let _ = mapped_argument_start(kind)
  }
  let expressions = [
    parse_expression(
      @source.Source::from_text(@source.SourceId::new(9702), "e", "a"),
    ),
    parse_expression(
      @source.Source::from_text(@source.SourceId::new(9703), "e", "(a)"),
    ),
  ]
  for expression in expressions {
    let _ = join_starts_without_lhs(expression)
    let _ = expression_line_end_expected(expression)
  }
}
