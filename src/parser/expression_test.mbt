///|
fn expression_source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(30), "expression", text)
}

///|
test "expression parser preserves precedence and byte spans" {
  let source = expression_source("a + b == c && d || e")
  let expression = @parser.parse_expression(source)
  guard expression is Binary(operator=Or, lhs~, rhs~, span~) else {
    fail("expected disjunction")
  }
  assert_eq(span, source.full_span())
  assert_true(lhs is Binary(operator=And, ..))
  assert_true(rhs is Variable(name="e", ..))
}

///|
test "calls, lists, joins, conditionals, and booleans parse" {
  let source = expression_source(
    "if a == 'x' { join(['a', 'b'], / 'c') } else { false }",
  )
  let expression = @parser.parse_expression(source)
  guard expression
    is Conditional(condition~, then_branch~, else_branch=Some(otherwise), ..) else {
    fail("expected conditional")
  }
  assert_true(condition is Binary(operator=Equal, ..))
  assert_true(then_branch is Call(name="join", ..))
  assert_true(otherwise is Boolean(value=false, ..))
}

///|
test "parser validates cooked and Unicode escapes" {
  let source = expression_source("\"line\\nsmile \\u{1F642}\"")
  guard @parser.parse_expression(source) is String(literal) else {
    fail("expected string")
  }
  assert_eq(literal.cooked(), "line\nsmile 🙂")
  let invalid = expression_source("\"bad \\q\"")
  try @parser.parse_expression(invalid) catch {
    InvalidEscapeSequence(character="q", span~) =>
      assert_eq(span, invalid.full_span())
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid escape")
  }
}

///|
test "triple strings remove common indentation and preserve CRLF blank lines" {
  guard @parser.parse_expression(
      expression_source("\"\"\"\n  foo\\\n  bar\n\"\"\""),
    )
    is String(cooked) else {
    fail("expected cooked triple string")
  }
  assert_eq(cooked.cooked(), "foobar\n")
  guard @parser.parse_expression(
      expression_source("'''\r\n  foo\r\n\r\n  bar\r\n'''"),
    )
    is String(raw) else {
    fail("expected raw triple string")
  }
  assert_eq(raw.cooked(), "foo\r\n\r\nbar\r\n")
  guard @parser.parse_expression(expression_source("\"a\\\r\nb\""))
    is String(continued) else {
    fail("expected CRLF continuation")
  }
  assert_eq(continued.cooked(), "ab")
}

///|
test "format strings retain literal and expression parts" {
  let source = expression_source("f'hello {{name}}!'")
  guard @parser.parse_expression(source) is Format(start~, parts~, span~) else {
    fail("expected format string")
  }
  assert_eq(start.cooked(), "hello ")
  assert_eq(parts.length(), 1)
  assert_true(parts[0].expression() is Variable(name="name", ..))
  assert_eq(parts[0].literal().cooked(), "!")
  assert_eq(span, source.full_span())
}

///|
test "expression parser enforces recursion and node budgets" {
  let source = expression_source("((((a))))")
  let limits = @parser.ParserLimits::new(2, 100, 4)
  try @parser.parse_expression(source, limits~) catch {
    RecursionLimitExceeded(limit=2, ..) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected recursion limit")
  }
  let nodes = expression_source("a + b + c")
  let limits = @parser.ParserLimits::new(32, 2, 4)
  try @parser.parse_expression(nodes, limits~) catch {
    NodeLimitExceeded(limit=2, ..) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected node limit")
  }
}
