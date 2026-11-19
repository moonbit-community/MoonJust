///|
/// Names accepted in setting declarations, in registry order.
pub fn setting_names() -> ArrayView[String] {
  @syntax.setting_specs().map(spec => spec.name())[:]
}

///|
fn Parser::parse_setting(
  self : Parser,
  start : @source.Span,
) -> @syntax.Setting raise ParserError {
  self.expect_identifier() |> ignore
  let (name, name_token) = self.expect_identifier()
  guard @syntax.setting_spec(name) is Some(spec) else {
    raise UnknownSetting(name~, span=name_token.span())
  }
  let value = if spec.kind() is Boolean {
    if self.accept(ColonEquals) is Some(_) {
      let token = self.peek()
      if token.kind() != Identifier {
        raise UnexpectedToken(
          expected="identifier",
          found=token.kind(),
          span=if token.kind() == Eol {
            @source.Span::new(
              token.span().source_id(),
              token.span().start_byte(),
              token.span().start_byte(),
            ) catch {
              _ => token.span()
            }
          } else {
            token.span()
          },
        )
      }
      let lexeme = self.lexeme(token)
      if lexeme != "true" && lexeme != "false" {
        raise UnexpectedConstruct(
          expected="keyword `true` or `false`",
          found="identifier `" + lexeme + "`",
          span=token.span(),
        )
      }
      self.advance() |> ignore
      Some(
        @syntax.Expression::Boolean(value=lexeme == "true", span=token.span()),
      )
    } else {
      None
    }
  } else {
    self.expect(ColonEquals) |> ignore
    if (
        name == "shell" ||
        name == "script-interpreter" ||
        name == "windows-shell"
      ) &&
      self.peek_kind() == BracketL &&
      self.peek_kind_at(1) == Some(BracketR) {
      self.advance() |> ignore
      let found = self.peek()
      raise UnexpectedToken(
        expected="expression",
        found=found.kind(),
        span=found.span(),
      )
    }
    Some(self.parse_expression_node())
  }
  let end_span = value
    .map(fn(value) { value.span() })
    .unwrap_or(name_token.span())
  @syntax.Setting::new(name, value, self.cover(start, end_span))
}

///|
fn Parser::parse_assignment(
  self : Parser,
  start : @source.Span,
  exported : Bool,
  eager : Bool,
  attributes : Array[@syntax.Attribute],
) -> @syntax.Assignment raise ParserError {
  let (name, name_token) = self.expect_identifier()
  self.expect(ColonEquals) |> ignore
  let value = self.parse_expression_node()
  @syntax.Assignment::new(
    name,
    name_span=name_token.span(),
    value,
    exported,
    eager,
    self.cover(start, value.span()),
    attributes~,
  )
}

///|
fn Parser::parse_function_definition(
  self : Parser,
  start : @source.Span,
  attributes : Array[@syntax.Attribute],
) -> @syntax.FunctionDefinition raise ParserError {
  let (name, _) = self.expect_identifier()
  self.expect(ParenL) |> ignore
  let parameters : Array[@syntax.FunctionParameter] = []
  while self.peek_kind() != ParenR {
    let (parameter, token) = self.expect_identifier()
    parameters.push(@syntax.FunctionParameter::new(parameter, token.span()))
    if self.accept(Comma) is None {
      break
    }
  }
  self.expect(ParenR) |> ignore
  self.expect(ColonEquals) |> ignore
  let body = self.parse_expression_node()
  @syntax.FunctionDefinition::new(
    name,
    parameters,
    body,
    attributes,
    self.cover(start, body.span()),
  )
}

///|
fn Parser::parse_alias(
  self : Parser,
  start : @source.Span,
  attributes : Array[@syntax.Attribute],
) -> @syntax.Alias raise ParserError {
  self.expect_identifier() |> ignore
  let (name, name_token) = self.expect_identifier()
  if self.accept(ColonEquals) is None {
    self.expect(Equals) |> ignore
  }
  let (target, target_span) = self.parse_namepath()
  @syntax.Alias::new(
    name,
    target,
    self.cover(start, target_span),
    name_span=name_token.span(),
    attributes~,
  )
}

///|
fn Parser::parse_import(
  self : Parser,
  start : @source.Span,
) -> @syntax.Import raise ParserError {
  self.expect_identifier() |> ignore
  let optional = self.accept(QuestionMark) is Some(_)
  if self.peek_kind() == Identifier && !self.peek_keyword(X) {
    let token = self.peek()
    raise UnexpectedConstruct(
      expected="keyword `x`",
      found="identifier `" + self.lexeme(token) + "`",
      span=token.span(),
    )
  }
  let path = self.parse_string_or_expanded_literal()
  @syntax.Import::new(path, optional, self.cover(start, path.span()))
}

///|
fn Parser::parse_module(
  self : Parser,
  start : @source.Span,
  attributes : Array[@syntax.Attribute],
) -> @syntax.Module raise ParserError {
  self.expect_identifier() |> ignore
  let optional = self.accept(QuestionMark) is Some(_)
  let (name, name_token) = self.expect_identifier()
  let path = if self.peek_kind() == StringToken ||
    self.shell_expanded_string_ahead() {
    Some(self.parse_string_or_expanded_literal())
  } else {
    None
  }
  let end_span = path
    .map(fn(value) { value.span() })
    .unwrap_or(name_token.span())
  @syntax.Module::new(
    name,
    name_token.span(),
    path,
    optional,
    self.cover(start, end_span),
    attributes~,
  )
}

///|
fn Parser::module_declaration_ahead(self : Parser) -> Bool {
  let mut offset = 1
  while self.peek_kind_at(offset) is Some(kind) {
    match kind {
      Colon => return false
      Eol | Eof | Comment => return true
      _ => offset += 1
    }
  }
  true
}

///|
