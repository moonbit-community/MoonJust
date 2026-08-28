///|
fn Parser::parse_namepath(
  self : Parser,
) -> (String, @source.Span) raise ParserError {
  let (first, first_token) = self.expect_identifier()
  if self.peek_kind() != ColonColon {
    return (first, first_token.span())
  }
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
fn Parser::unparenthesized_join_span(
  self : Parser,
  expression : @syntax.Expression,
) -> @source.Span? {
  match expression {
    Binary(operator=Join, lhs~, rhs~, ..) => {
      let start = if lhs.span().is_empty() {
        Int::max(lhs.span().start_byte() - 1, 0)
      } else {
        lhs.span().end_byte()
      }
      for index in start..<rhs.span().start_byte() {
        if self.source.bytes()[index] == b'/' {
          return Some(
            @source.Span::new(self.source.id(), index, index + 1) catch {
              _ => expression.span()
            },
          )
        }
      }
      Some(expression.span())
    }
    Binary(lhs~, rhs~, ..) =>
      match self.unparenthesized_join_span(lhs) {
        Some(span) => Some(span)
        None => self.unparenthesized_join_span(rhs)
      }
    Unary(operand~, ..) => self.unparenthesized_join_span(operand)
    _ => None
  }
}

///|
fn join_starts_without_lhs(expression : @syntax.Expression) -> Bool {
  match expression {
    Binary(operator=Join, lhs~, ..) => lhs.span().is_empty()
    Parenthesized(_) => false
    _ => false
  }
}

///|
fn Parser::parse_parameter_default(
  self : Parser,
) -> @syntax.Expression raise ParserError {
  self.parsing_parameter_default = true
  defer {
    self.parsing_parameter_default = false
  }
  let expression = self.parse_value()
  match self.unparenthesized_join_span(expression) {
    Some(span) =>
      raise UnexpectedToken(
        expected=if join_starts_without_lhs(expression) {
          "backtick, '!', '[', identifier, '(', or string"
        } else {
          "'*', ':', '$', identifier, or '+'"
        },
        found=Slash,
        span~,
      )
    None => expression
  }
}

///|
fn Parser::parse_parameter(
  self : Parser,
  variadic : Bool,
) -> @syntax.Parameter raise ParserError {
  let exported = self.accept(Dollar) is Some(_)
  let (name, name_token) = self.expect_identifier()
  let default_value = if self.accept(Equals) is Some(_) {
    Some(self.parse_parameter_default())
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
fn mapped_argument_start(kind : @lexer.TokenKind) -> Bool {
  match kind {
    Asterisk
    | Backtick
    | Bang
    | BracketL
    | Identifier
    | ParenL
    | ParenR
    | Slash
    | StringToken => true
    _ => false
  }
}

///|
fn Parser::parse_dependency(
  self : Parser,
) -> @syntax.Dependency raise ParserError {
  let start = self.peek()
  if self.accept(Asterisk) is Some(_) {
    self.expect(ParenL) |> ignore
    let (name, name_span) = self.parse_namepath()
    let arguments : Array[@syntax.Expression] = []
    let starred_arguments : Array[Int] = []
    while self.peek_kind() != ParenR {
      if !mapped_argument_start(self.peek_kind()) {
        let found = self.peek()
        raise UnexpectedToken(
          expected="'*', backtick, '!', '[', identifier, '(', ')', '/', or string",
          found=found.kind(),
          span=found.span(),
        )
      }
      let starred = self.accept(Asterisk) is Some(_)
      if starred {
        starred_arguments.push(arguments.length())
      }
      arguments.push(
        if starred {
          if !mapped_argument_start(self.peek_kind()) {
            let found = self.peek()
            raise UnexpectedToken(
              expected="'*', backtick, '!', '[', identifier, '(', ')', '/', or string",
              found=found.kind(),
              span=found.span(),
            )
          }
          self.parse_value()
        } else {
          self.parse_expression_node()
        },
      )
      self.accept(Comma) |> ignore
    }
    let close = self.expect(ParenR)
    return @syntax.Dependency::new(
      name,
      name_span,
      arguments,
      true,
      self.cover(start.span(), close.span()),
      starred_arguments~,
    )
  }
  if self.accept(ParenL) is Some(_) {
    let (name, name_span) = self.parse_namepath()
    let arguments : Array[@syntax.Expression] = []
    let starred_arguments : Array[Int] = []
    while self.peek_kind() != ParenR {
      if !mapped_argument_start(self.peek_kind()) {
        let found = self.peek()
        raise UnexpectedToken(
          expected="'*', backtick, '!', '[', identifier, '(', ')', '/', or string",
          found=found.kind(),
          span=found.span(),
        )
      }
      let starred = self.accept(Asterisk) is Some(_)
      if starred {
        starred_arguments.push(arguments.length())
      }
      arguments.push(
        if starred {
          if !mapped_argument_start(self.peek_kind()) {
            let found = self.peek()
            raise UnexpectedToken(
              expected="'*', backtick, '!', '[', identifier, '(', ')', '/', or string",
              found=found.kind(),
              span=found.span(),
            )
          }
          self.parse_value()
        } else {
          self.parse_expression_node()
        },
      )
      self.accept(Comma) |> ignore
    }
    let close = self.expect(ParenR)
    return @syntax.Dependency::new(
      name,
      name_span,
      arguments,
      false,
      self.cover(start.span(), close.span()),
      starred_arguments~,
    )
  }
  let (name, span) = self.parse_namepath()
  @syntax.Dependency::new(name, span, [], false, span)
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
              let close = if self.peek_kind() == InterpolationEnd {
                self.advance()
              } else {
                let found = self.peek()
                raise UnexpectedToken(
                  expected="'&&', '!=', '!~', '||', '==', '=~', '}}', '(', '+', '++', or '/'",
                  found=found.kind(),
                  span=found.span(),
                )
              }
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
    let span = self.cover(start_span, end_span)
    let source_start_line = try! self.source.locate(span.start_byte()).line()
    let source_end_line = try! self.source.locate(end_span.start_byte()).line()
    lines.push(
      @syntax.RecipeLine::new(
        fragments,
        span,
        source_start_line~,
        source_end_line~,
      ),
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
  prefetched_name : (String, @lexer.Token)?,
) -> @syntax.Recipe raise ParserError {
  let start = self.peek().span()
  let (name, name_token) = match prefetched_name {
    Some(value) => {
      self.advance() |> ignore
      value
    }
    None => self.expect_identifier()
  }
  let parameters : Array[@syntax.Parameter] = []
  while self.peek_kind() == Identifier || self.peek_kind() == Dollar {
    parameters.push(self.parse_parameter(false))
  }
  let mut variadic = false
  if self.accept(Plus) is Some(_) {
    variadic = true
    parameters.push(self.parse_parameter(true))
  } else if self.accept(Asterisk) is Some(_) {
    variadic = true
    let exported = self.accept(Dollar) is Some(_)
    let (name, token) = self.expect_identifier()
    let default_value = if self.accept(Equals) is Some(_) {
      Some(self.parse_parameter_default())
    } else {
      None
    }
    parameters.push(
      @syntax.Parameter::new_star(name, exported, token.span(), default_value?),
    )
  }
  if self.peek_kind() == Plus || self.peek_kind() == Asterisk {
    let found = self.peek()
    raise UnexpectedToken(
      expected="':' or '='",
      found=found.kind(),
      span=found.span(),
    )
  }
  while self.peek_kind() == Identifier || self.peek_kind() == Dollar {
    if variadic {
      let found = self.peek()
      raise UnexpectedConstruct(
        expected="no parameters after variadic parameter",
        found=self.lexeme(found),
        span=found.span(),
      )
    }
    parameters.push(self.parse_parameter(false))
  }
  if self.accept(Colon) is None {
    let found = self.peek()
    raise UnexpectedToken(
      expected="'*', ':', '$', identifier, or '+'",
      found=found.kind(),
      span=found.span(),
    )
  }
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
  let trailing_comment = match self.accept(Comment) {
    Some(comment) => Some(self.lexeme(comment))
    None => None
  }
  self.consume_line_end_expected(
    "'&&', '*', comment, end of file, end of line, identifier, indent, or '('",
  )
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
    trailing_comment?,
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
      Some(@syntax.Boolean(value=lexeme == "true", span=token.span()))
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
  let (name, _) = self.expect_identifier()
  self.expect(ColonEquals) |> ignore
  let value = self.parse_expression_node()
  @syntax.Assignment::new(
    name,
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
  let (name, _) = self.expect_identifier()
  if self.accept(ColonEquals) is None {
    self.expect(Equals) |> ignore
  }
  let (target, target_span) = self.parse_namepath()
  @syntax.Alias::new(name, target, self.cover(start, target_span), attributes~)
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
fn Parser::parse_item(
  self : Parser,
  attributes : Array[@syntax.Attribute],
) -> @syntax.Item raise ParserError {
  let start = self.peek().span()
  if self.peek_kind() == At {
    self.advance() |> ignore
    return Recipe(self.parse_recipe(true, attributes, None))
  }
  let mut prefetched_name : (String, @lexer.Token)? = None
  let keyword = if self.peek_kind() == Identifier {
    let token = self.peek()
    let name = self.lexeme(token)
    prefetched_name = Some((name, token))
    @lexer.Keyword::from_lexeme(name)
  } else {
    None
  }
  match keyword {
    Some(Export) if self.peek_kind_at(2) == Some(ColonEquals) => {
      self.advance() |> ignore
      Assignment(self.parse_assignment(start, true, false, attributes))
    }
    Some(Eager) if self.peek_kind_at(2) == Some(ColonEquals) => {
      self.advance() |> ignore
      Assignment(self.parse_assignment(start, false, true, attributes))
    }
    _ if self.peek_kind_at(1) == Some(ColonEquals) =>
      Assignment(self.parse_assignment(start, false, false, attributes))
    _ if self.peek_kind_at(1) == Some(ParenL) =>
      Function(self.parse_function_definition(start, attributes))
    Some(Alias) if self.peek_kind_at(2) == Some(ColonEquals) =>
      Alias(self.parse_alias(start, attributes))
    Some(Set) => Setting(self.parse_setting(start))
    Some(Import) => Import(self.parse_import(start))
    Some(Mod) if self.module_declaration_ahead() =>
      Module(self.parse_module(start, attributes))
    Some(Unexport) if self.peek_kind_at(1) == Some(Identifier) &&
      (
        self.peek_kind_at(2) == Some(Eol) ||
        self.peek_kind_at(2) == Some(Comment) ||
        self.peek_kind_at(2) == Some(Eof)
      ) => {
      self.advance() |> ignore
      let (name, name_token) = self.expect_identifier()
      Unexport(name~, span=self.cover(start, name_token.span()))
    }
    _ => Recipe(self.parse_recipe(false, attributes, prefetched_name))
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
    let mut attribute_start : @source.Span? = None
    while self.peek_kind() == BracketL {
      if attribute_start is None {
        attribute_start = Some(self.peek().span())
      }
      for attribute in self.parse_attribute_group() {
        attributes.push(attribute)
      }
    }
    if !attributes.is_empty() &&
      (self.peek_kind() == Comment || self.peek_kind() == Eol) {
      raise ExtraneousAttribute(span=attribute_start.unwrap())
    }
    if !attributes.is_empty() && self.peek_kind() == Eof {
      let found = self.peek()
      raise UnexpectedToken(
        expected="'@', '[', comment, end of line, or identifier",
        found=found.kind(),
        span=found.span(),
      )
    }
    if self.peek_kind() == Eof {
      break
    }
    if self.peek_kind() != At && self.peek_kind() != Identifier {
      let found = self.peek()
      raise UnexpectedToken(
        expected="'@', '[', comment, end of file, end of line, or identifier",
        found=found.kind(),
        span=found.span(),
      )
    }
    let item = self.parse_item(attributes)
    match item {
      Setting(_) | Import(_) | Unexport(_) =>
        for attribute in attributes {
          items.push(Attribute(attribute))
        }
      _ => ()
    }
    items.push(item)
    match item {
      Recipe(_) => ()
      _ => {
        match self.accept(Comment) {
          Some(comment) =>
            items.push(
              TrailingComment(text=self.lexeme(comment), span=comment.span()),
            )
          None => ()
        }
        let expected = match item {
          Assignment(value) => expression_line_end_expected(value.value())
          Function(value) => expression_line_end_expected(value.body())
          Setting(value) =>
            value
            .value()
            .map(expression_line_end_expected)
            .unwrap_or("end-of-line")
          _ => "end-of-line"
        }
        self.consume_line_end_expected(expected)
      }
    }
  }
  @syntax.Ast::new(self.source.id(), items, self.source.full_span())
}

///|
fn expression_line_end_expected(expression : @syntax.Expression) -> String {
  match expression {
    Binary(operator=Equal | NotEqual | RegexMatch | RegexNotMatch, ..) =>
      "'&&', '||', comment, end of file, end of line, '+', '++', or '/'"
    Conditional(_) =>
      "'&&', '!=', '!~', '||', comment, end of file, end of line, '==', or '=~'"
    _ =>
      "'&&', '!=', '!~', '||', comment, end of file, end of line, '==', '=~', '(', '+', '++', or '/'"
  }
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
/// Parse a token stream while resolving shell-expanded string literals from
/// the caller-provided host environment.
pub fn parse_tokens_with_environment(
  source : @source.Source,
  stream : @lexer.TokenStream,
  environment : ArrayView[(String, String)],
  limits? : ParserLimits = ParserLimits::default(),
) -> @syntax.Ast raise ParserError {
  Parser::new(source, stream, limits, environment~).parse_ast()
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

///|
/// Lex and parse a justfile with the environment used by `x'…'` literals.
pub fn parse_with_environment(
  source : @source.Source,
  environment : ArrayView[(String, String)],
  limits? : ParserLimits = ParserLimits::default(),
) -> @syntax.Ast raise ParserError {
  let stream = @lexer.lex(source) catch { error => raise LexerFailure(error) }
  parse_tokens_with_environment(source, stream, environment, limits~)
}
