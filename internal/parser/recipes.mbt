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
