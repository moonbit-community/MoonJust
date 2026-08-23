///|
test "syntax semantic fingerprints cover every AST node family" {
  let source_id = @source.SourceId::new(9930)
  let span = @source.Span::new(source_id, 0, 1)
  let raw = @syntax.StringLiteral::new("'raw'", "raw", Raw, span)
  let cooked = @syntax.StringLiteral::new(
    "\"cooked\"",
    "cooked",
    Cooked,
    span,
    shell_expanded=true,
  )
  let backtick = @syntax.StringLiteral::new("`echo`", "echo", Backtick, span)
  let triple_raw = @syntax.StringLiteral::new(
    "'''raw'''",
    "raw",
    TripleRaw,
    span,
  )
  let triple_cooked = @syntax.StringLiteral::new(
    "\"\"\"cooked\"\"\"",
    "cooked",
    TripleCooked,
    span,
  )
  for literal in [raw, cooked, backtick, triple_raw, triple_cooked] {
    assert_true(literal.raw().length() > 0)
    assert_true(literal.cooked().length() >= 0)
    assert_true(literal.span() == span)
    ignore(literal.shell_expanded())
  }
  let variable : @syntax.Expression = Variable(name="name", span~)
  let string : @syntax.Expression = String(raw)
  let back : @syntax.Expression = Backtick(backtick)
  let boolean : @syntax.Expression = Boolean(value=true, span~)
  let call : @syntax.Expression = Call(
    name="f",
    arguments=[string, variable],
    span~,
  )
  let list : @syntax.Expression = List(elements=[string, boolean], span~)
  let parenthesized : @syntax.Expression = Parenthesized(
    expression=variable,
    span~,
  )
  let unary : @syntax.Expression = Unary(operator=Not, operand=boolean, span~)
  let operators : Array[@syntax.BinaryOperator] = [
    Or,
    And,
    Equal,
    NotEqual,
    RegexMatch,
    RegexNotMatch,
    ListConcat,
    Concat,
    Join,
  ]
  for operator in operators {
    let expression : @syntax.Expression = Binary(
      operator~,
      operator_span=span,
      lhs=variable,
      rhs=string,
      span~,
    )
    assert_true(expression.semantic_key().length() > 0)
    assert_true(expression.kind() == "binary")
  }
  let conditional : @syntax.Expression = Conditional(
    condition=boolean,
    then_branch=string,
    else_branch=Some(back),
    span~,
  )
  let format : @syntax.Expression = Format(
    start=cooked,
    parts=[@syntax.FormatPart::new(variable, raw)],
    span~,
  )
  for
    expression in [
      string, back, boolean, variable, call, list, parenthesized, unary, conditional,
      format,
    ] {
    assert_true(expression.semantic_key().length() > 0)
    assert_true(expression.span() == span)
    assert_true(expression.kind().length() > 0)
  }
  let argument = @syntax.AttributeArgument::new(Some("key"), Some(string), span)
  let attribute = @syntax.Attribute::new("doc", [argument], span)
  let parameter = @syntax.Parameter::new("x", Some(string), false, true, span)
  let star = @syntax.Parameter::new_star("rest", false, span)
  let dependency = @syntax.Dependency::new(
    "dep",
    span,
    [variable],
    true,
    span,
    starred_arguments=[0],
  )
  let line = @syntax.RecipeLine::new(
    [Text(text="echo ", span~), Interpolation(expression=variable, span~)],
    span,
    source_start_line=2,
    source_end_line=3,
  )
  let assignment = @syntax.Assignment::new("X", string, true, false, span, attributes=[
    attribute,
  ])
  let function_item = @syntax.FunctionDefinition::new(
    "f",
    [@syntax.FunctionParameter::new("x", span)],
    call,
    [attribute],
    span,
  )
  let alias_item = @syntax.Alias::new("build", "compile", span, attributes=[
    attribute,
  ])
  let setting = @syntax.Setting::new("quiet", Some(boolean), span)
  let import_item = @syntax.Import::new(raw, true, span)
  let module_item = @syntax.Module::new(
    "tools",
    span,
    Some(cooked),
    false,
    span,
    attributes=[attribute],
  )
  let recipe = @syntax.Recipe::new(
    "build",
    true,
    [parameter, star],
    [dependency],
    [@syntax.Dependency::new("cleanup", span, [], false, span)],
    [line],
    [attribute],
    span,
    trailing_comment="docs",
  )
  let items : Array[@syntax.Item] = [
    Assignment(assignment),
    Function(function_item),
    Alias(alias_item),
    Recipe(recipe),
    Setting(setting),
    Attribute(attribute),
    Import(import_item),
    Module(module_item),
    Unexport(name="X", span~),
    Comment(text="comment", span~),
    TrailingComment(text="trailing", span~),
    Blank(span~),
  ]
  let ast = @syntax.Ast::new(source_id, items, span)
  let key = ast.semantic_key()
  assert_true(key.contains("assignment:X"))
  assert_true(key.contains("recipe:build"))
  for item in ast.items() {
    assert_true(item.span() == span)
    ignore(item.name())
    assert_true(item.semantic_key().length() > 0)
  }
}
