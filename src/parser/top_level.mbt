///|
fn Parser::parse_namepath(
  self : Parser,
) -> (String, @source.Span) raise ParserError {
  let (first, first_token) = self.expect_identifier()
  let builder = StringBuilder()
  builder.write_string(first)
  let mut last = first_token.span()
  while self.accept(ColonColon) is Some(_) {
    let (part, token) = self.expect_identifier()
    builder.write_string("::")
    builder.write_string(part)
    last = token.span()
  }
  (builder.to_string(), self.cover(first_token.span(), last))
}

///|
fn Parser::parse_parameter(
  self : Parser,
  variadic : Bool,
) -> @syntax.Parameter raise ParserError {
  let exported = self.accept(Dollar) is Some(_)
  let (name, name_token) = self.expect_identifier()
  let default_value = if self.accept(Equals) is Some(_) {
    Some(self.parse_expression_node())
  } else {
    None
  }
  @syntax.Parameter::new(
    name,
    default_value,
    variadic,
    exported,
    name_token.span(),
  )
}

///|
fn Parser::parse_dependency(
  self : Parser,
) -> @syntax.Dependency raise ParserError {
  let start = self.peek()
  if self.accept(Asterisk) is Some(_) {
    self.expect(ParenL) |> ignore
    let (name, _) = self.parse_namepath()
    let arguments : Array[@syntax.Expression] = []
    while self.peek_kind() != ParenR {
      self.accept(Asterisk) |> ignore
      arguments.push(self.parse_expression_node())
      if self.accept(Comma) is None {
        break
      }
    }
    let close = self.expect(ParenR)
    return @syntax.Dependency::new(
      name,
      arguments,
      true,
      self.cover(start.span(), close.span()),
    )
  }
  if self.accept(ParenL) is Some(_) {
    let (name, _) = self.parse_namepath()
    let arguments : Array[@syntax.Expression] = []
    while self.peek_kind() != ParenR {
      arguments.push(self.parse_expression_node())
      if self.accept(Comma) is None {
        break
      }
    }
    let close = self.expect(ParenR)
    return @syntax.Dependency::new(
      name,
      arguments,
      false,
      self.cover(start.span(), close.span()),
    )
  }
  let (name, span) = self.parse_namepath()
  @syntax.Dependency::new(name, [], false, span)
}

///|
fn Parser::parse_recipe_body(
  self : Parser,
) -> Array[@syntax.RecipeLine] raise ParserError {
  let lines : Array[@syntax.RecipeLine] = []
  if self.accept(Indent) is None {
    return lines
  }
  while self.peek_kind() != Dedent && self.peek_kind() != Eof {
    let mut start_span = self.peek().span()
    let fragments : Array[@syntax.RecipeFragment] = []
    while self.peek_kind() != Eol &&
          self.peek_kind() != Dedent &&
          self.peek_kind() != Eof {
      match self.accept(Text) {
        Some(token) => {
          if fragments.is_empty() {
            start_span = token.span()
          }
          fragments.push(Text(text=self.lexeme(token), span=token.span()))
        }
        None =>
          match self.accept(InterpolationStart) {
            Some(open) => {
              let expression = self.parse_expression_node()
              let close = self.expect(InterpolationEnd)
              let span = self.cover(open.span(), close.span())
              if fragments.is_empty() {
                start_span = open.span()
              }
              fragments.push(Interpolation(expression~, span~))
            }
            None => {
              let found = self.peek()
              raise UnexpectedToken(
                expected="recipe text or interpolation",
                found=found.kind(),
                span=found.span(),
              )
            }
          }
      }
    }
    let end_span = if self.peek_kind() == Eol {
      self.advance().span()
    } else {
      start_span.at_end()
    }
    lines.push(
      @syntax.RecipeLine::new(fragments, self.cover(start_span, end_span)),
    )
  }
  self.accept(Dedent) |> ignore
  lines
}

///|
fn Parser::parse_recipe(
  self : Parser,
  quiet : Bool,
  attributes : Array[@syntax.Attribute],
) -> @syntax.Recipe raise ParserError {
  let start = self.peek().span()
  let (name, name_token) = self.expect_identifier()
  let parameters : Array[@syntax.Parameter] = []
  while self.peek_kind() == Identifier || self.peek_kind() == Dollar {
    parameters.push(self.parse_parameter(false))
  }
  if self.accept(Plus) is Some(_) || self.accept(Asterisk) is Some(_) {
    parameters.push(self.parse_parameter(true))
  }
  self.expect(Colon) |> ignore
  let dependencies : Array[@syntax.Dependency] = []
  while self.peek_kind() == Identifier ||
        self.peek_kind() == ParenL ||
        self.peek_kind() == Asterisk {
    dependencies.push(self.parse_dependency())
  }
  let subsequent : Array[@syntax.Dependency] = []
  if self.accept(AmpersandAmpersand) is Some(_) {
    if self.line_finished() {
      raise UnexpectedToken(
        expected="subsequent dependency",
        found=self.peek_kind(),
        span=self.peek().span(),
      )
    }
    while self.peek_kind() == Identifier ||
          self.peek_kind() == ParenL ||
          self.peek_kind() == Asterisk {
      subsequent.push(self.parse_dependency())
    }
  }
  self.consume_line_end()
  let lines = self.parse_recipe_body()
  let end_span = if lines.length() > 0 {
    lines[lines.length() - 1].span()
  } else {
    name_token.span()
  }
  @syntax.Recipe::new(
    name,
    quiet,
    parameters,
    dependencies,
    subsequent,
    lines,
    attributes,
    self.cover(start, end_span),
  )
}

///|
fn setting_known(name : String) -> Bool {
  setting_names().contains(name)
}

///|
fn setting_is_boolean(name : String) -> Bool {
  match name {
    "allow-duplicate-recipes"
    | "allow-duplicate-variables"
    | "default-list"
    | "default-script"
    | "dotenv-load"
    | "dotenv-override"
    | "dotenv-required"
    | "export"
    | "fallback"
    | "guards"
    | "ignore-comments"
    | "lazy"
    | "lists"
    | "no-cd"
    | "no-exit-message"
    | "positional-arguments"
    | "quiet"
    | "unstable"
    | "windows-powershell" => true
    _ => false
  }
}

///|
/// Return the complete stable settings inventory from `just 1.57.0`.
pub fn setting_names() -> ArrayView[String] {
  [
    "allow-duplicate-recipes", "allow-duplicate-variables", "default-list", "default-script",
    "dotenv-command", "dotenv-filename", "dotenv-load", "dotenv-override", "dotenv-path",
    "dotenv-required", "export", "fallback", "guards", "ignore-comments", "indentation",
    "lazy", "lists", "minimum-version", "no-cd", "no-exit-message", "positional-arguments",
    "quiet", "script-interpreter", "shell", "tempdir", "unstable", "windows-powershell",
    "windows-shell", "working-directory",
  ][:]
}

///|
fn Parser::parse_setting(
  self : Parser,
  start : @source.Span,
) -> @syntax.Setting raise ParserError {
  self.expect_identifier() |> ignore
  let (name, name_token) = self.expect_identifier()
  if !setting_known(name) {
    raise UnknownSetting(name~, span=name_token.span())
  }
  let value = if setting_is_boolean(name) {
    if self.accept(ColonEquals) is Some(_) {
      let expression = self.parse_expression_node()
      match expression {
        Boolean(_) => Some(expression)
        _ => raise InvalidSettingValue(name~, span=expression.span())
      }
    } else {
      None
    }
  } else {
    self.expect(ColonEquals) |> ignore
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
) -> @syntax.Assignment raise ParserError {
  let (name, _) = self.expect_identifier()
  self.expect(ColonEquals) |> ignore
  let value = self.parse_expression_node()
  @syntax.Assignment::new(
    name,
    value,
    exported,
    eager,
    self.cover(start, value.span()),
  )
}

///|
fn Parser::parse_alias(
  self : Parser,
  start : @source.Span,
) -> @syntax.Alias raise ParserError {
  self.expect_identifier() |> ignore
  let (name, _) = self.expect_identifier()
  if self.accept(ColonEquals) is None {
    self.expect(Equals) |> ignore
  }
  let (target, target_span) = self.parse_namepath()
  @syntax.Alias::new(name, target, self.cover(start, target_span))
}

///|
fn Parser::parse_import(
  self : Parser,
  start : @source.Span,
) -> @syntax.Import raise ParserError {
  self.expect_identifier() |> ignore
  let optional = self.accept(QuestionMark) is Some(_)
  let path = self.parse_plain_literal(StringToken)
  @syntax.Import::new(path, optional, self.cover(start, path.span()))
}

///|
fn Parser::parse_module(
  self : Parser,
  start : @source.Span,
) -> @syntax.Module raise ParserError {
  self.expect_identifier() |> ignore
  let optional = self.accept(QuestionMark) is Some(_)
  let (name, name_token) = self.expect_identifier()
  let path = if self.peek_kind() == StringToken {
    Some(self.parse_plain_literal(StringToken))
  } else {
    None
  }
  let end_span = path
    .map(fn(value) { value.span() })
    .unwrap_or(name_token.span())
  @syntax.Module::new(name, path, optional, self.cover(start, end_span))
}

///|
fn Parser::parse_item(
  self : Parser,
  attributes : Array[@syntax.Attribute],
) -> @syntax.Item raise ParserError {
  let start = self.peek().span()
  if self.peek_kind() == At {
    self.advance() |> ignore
    return Recipe(self.parse_recipe(true, attributes))
  }
  let keyword = if self.peek_kind() == Identifier {
    @lexer.Keyword::from_lexeme(self.lexeme(self.peek()))
  } else {
    None
  }
  match keyword {
    Some(Export) if self.peek_kind_at(2) == Some(ColonEquals) => {
      self.advance() |> ignore
      Assignment(self.parse_assignment(start, true, false))
    }
    Some(Eager) if self.peek_kind_at(2) == Some(ColonEquals) => {
      self.advance() |> ignore
      Assignment(self.parse_assignment(start, false, true))
    }
    _ if self.peek_kind_at(1) == Some(ColonEquals) =>
      Assignment(self.parse_assignment(start, false, false))
    Some(Alias) => Alias(self.parse_alias(start))
    Some(Set) => Setting(self.parse_setting(start))
    Some(Import) => Import(self.parse_import(start))
    Some(Mod) => Module(self.parse_module(start))
    Some(Unexport) => {
      self.advance() |> ignore
      let (name, name_token) = self.expect_identifier()
      Unexport(name~, span=self.cover(start, name_token.span()))
    }
    _ => Recipe(self.parse_recipe(false, attributes))
  }
}

///|
fn Parser::parse_ast(self : Parser) -> @syntax.Ast raise ParserError {
  self.accept(ByteOrderMark) |> ignore
  let items : Array[@syntax.Item] = []
  while self.peek_kind() != Eof {
    if self.peek_kind() == Eol {
      let token = self.advance()
      items.push(Blank(span=token.span()))
      continue
    }
    match self.accept(Comment) {
      Some(comment) => {
        items.push(Comment(text=self.lexeme(comment), span=comment.span()))
        self.consume_line_end()
        continue
      }
      None => ()
    }
    let attributes : Array[@syntax.Attribute] = []
    while self.peek_kind() == BracketL {
      for attribute in self.parse_attribute_group() {
        attributes.push(attribute)
      }
    }
    if self.peek_kind() == Eof {
      break
    }
    let item = self.parse_item(attributes)
    items.push(item)
    match item {
      Recipe(_) => ()
      _ => self.consume_line_end()
    }
  }
  @syntax.Ast::new(self.source.id(), items, self.source.full_span())
}

///|
/// Parse a token stream into the target-independent syntax tree.
pub fn parse_tokens(
  source : @source.Source,
  stream : @lexer.TokenStream,
  limits? : ParserLimits = ParserLimits::default(),
) -> @syntax.Ast raise ParserError {
  Parser::new(source, stream, limits).parse_ast()
}

///|
/// Lex and parse one complete justfile source.
pub fn parse(
  source : @source.Source,
  limits? : ParserLimits = ParserLimits::default(),
) -> @syntax.Ast raise ParserError {
  let stream = @lexer.lex(source) catch { error => raise LexerFailure(error) }
  parse_tokens(source, stream, limits~)
}
