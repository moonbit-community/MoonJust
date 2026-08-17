///|
fn Parser::parse_expression_node(
  self : Parser,
) -> @syntax.Expression raise ParserError {
  self.enter()
  let result = self.parse_or()
  self.leave()
  result
}

///|
fn Parser::parse_or(self : Parser) -> @syntax.Expression raise ParserError {
  let lhs = self.parse_and()
  match self.accept(BarBar) {
    Some(operator_token) => {
      let rhs = self.parse_or()
      let span = self.cover(lhs.span(), rhs.span())
      self.node(span)
      Binary(
        operator=Or,
        operator_span=operator_token.span(),
        lhs~,
        rhs~,
        span~,
      )
    }
    None => lhs
  }
}

///|
fn Parser::parse_and(self : Parser) -> @syntax.Expression raise ParserError {
  let lhs = self.parse_comparison()
  match self.accept(AmpersandAmpersand) {
    Some(operator_token) => {
      let rhs = self.parse_and()
      let span = self.cover(lhs.span(), rhs.span())
      self.node(span)
      Binary(
        operator=And,
        operator_span=operator_token.span(),
        lhs~,
        rhs~,
        span~,
      )
    }
    None => lhs
  }
}

///|
fn Parser::parse_comparison(
  self : Parser,
) -> @syntax.Expression raise ParserError {
  let lhs = self.parse_concatenation()
  let operator : @syntax.BinaryOperator? = match self.peek_kind() {
    EqualsEquals => Some(Equal)
    BangEquals => Some(NotEqual)
    EqualsTilde => Some(RegexMatch)
    BangTilde => Some(RegexNotMatch)
    _ => None
  }
  match operator {
    None => lhs
    Some(operator) => {
      let operator_token = self.advance()
      let rhs = self.parse_concatenation()
      let span = self.cover(lhs.span(), rhs.span())
      self.node(span)
      Binary(operator~, operator_span=operator_token.span(), lhs~, rhs~, span~)
    }
  }
}

///|
fn Parser::parse_concatenation(
  self : Parser,
) -> @syntax.Expression raise ParserError {
  if self.accept(Slash) is Some(operator) {
    let rhs = self.parse_concatenation()
    let empty_span = operator.span().at_end()
    let empty : @syntax.Expression = String(
      @syntax.StringLiteral::new("", "", Raw, empty_span),
    )
    let span = self.cover(operator.span(), rhs.span())
    self.node(span)
    return Binary(
      operator=Join,
      operator_span=operator.span(),
      lhs=empty,
      rhs~,
      span~,
    )
  }
  let lhs = self.parse_value()
  if self.parsing_parameter_default && self.peek_kind() == Plus {
    let parameter_boundary = self.peek_kind_at(1) == Some(Dollar) ||
      (
        self.peek_kind_at(1) == Some(Identifier) &&
        (
          self.peek_kind_at(2) == Some(Equals) ||
          self.peek_kind_at(2) == Some(Colon)
        )
      )
    if parameter_boundary {
      return lhs
    }
  }
  let operator : @syntax.BinaryOperator? = match self.peek_kind() {
    Plus => Some(Concat)
    PlusPlus => Some(ListConcat)
    Slash => Some(Join)
    _ => None
  }
  match operator {
    None => lhs
    Some(operator) => {
      let operator_token = self.advance()
      let rhs = self.parse_concatenation()
      let span = self.cover(lhs.span(), rhs.span())
      self.node(span)
      Binary(operator~, operator_span=operator_token.span(), lhs~, rhs~, span~)
    }
  }
}

///|
fn Parser::parse_call(
  self : Parser,
  name : String,
  name_span : @source.Span,
) -> @syntax.Expression raise ParserError {
  self.expect(ParenL) |> ignore
  let arguments : Array[@syntax.Expression] = []
  while self.peek_kind() != ParenR {
    arguments.push(self.parse_expression_node())
    if self.accept(Comma) is None {
      break
    }
  }
  let close = self.expect(ParenR)
  let span = self.cover(name_span, close.span())
  self.node(span)
  Call(name~, arguments~, span~)
}

///|
fn Parser::parse_conditional(
  self : Parser,
) -> @syntax.Expression raise ParserError {
  let start = self.advance()
  let condition = self.parse_expression_node()
  if self.peek_kind() != BraceL {
    let found = self.peek()
    raise UnexpectedToken(
      expected="'&&', '!=', '!~', '||', '{', '==', '=~', '+', '++', or '/'",
      found=found.kind(),
      span=found.span(),
    )
  }
  self.advance() |> ignore
  let then_branch = self.parse_expression_node()
  let close = self.expect(BraceR)
  let mut end_span = close.span()
  let else_branch = if self.accept_keyword(Else) is Some(_) {
    let branch = if self.peek_keyword(If) {
      self.parse_conditional()
    } else {
      self.expect(BraceL) |> ignore
      let value = self.parse_expression_node()
      let close = self.expect(BraceR)
      end_span = close.span()
      value
    }
    end_span = branch.span()
    Some(branch)
  } else {
    None
  }
  let span = self.cover(start.span(), end_span)
  self.node(span)
  Conditional(condition~, then_branch~, else_branch~, span~)
}

///|
fn Parser::parse_list(self : Parser) -> @syntax.Expression raise ParserError {
  let open = self.advance()
  let elements : Array[@syntax.Expression] = []
  while self.peek_kind() != BracketR {
    elements.push(self.parse_expression_node())
    if self.accept(Comma) is None {
      break
    }
  }
  let close = self.expect(BracketR)
  let span = self.cover(open.span(), close.span())
  self.node(span)
  List(elements~, span~)
}

///|
fn Parser::parse_format(self : Parser) -> @syntax.Expression raise ParserError {
  let prefix = self.advance()
  let token = self.advance()
  let raw = self.lexeme(token)
  let (kind, delimiter, _) = literal_parts(raw)
  if token.kind() == StringToken {
    let literal = self.format_segment(token, true, true, kind, delimiter)
    self.node(self.cover(prefix.span(), token.span()))
    return Format(
      start=literal,
      parts=[],
      span=self.cover(prefix.span(), token.span()),
    )
  }
  let start = self.format_segment(token, true, false, kind, delimiter)
  let parts : Array[@syntax.FormatPart] = []
  let mut end_span = token.span()
  while true {
    let expression = self.parse_expression_node()
    let continuation = self.advance()
    if continuation.kind() != FormatStringContinue &&
      continuation.kind() != FormatStringEnd {
      raise UnexpectedToken(
        expected="'&&', '!=', '!~', '||', '==', '=~', format string continue, format string end, '(', '+', '++', or '/'",
        found=continuation.kind(),
        span=continuation.span(),
      )
    }
    let last = continuation.kind() == FormatStringEnd
    let literal = self.format_segment(
      continuation, false, last, kind, delimiter,
    )
    parts.push(@syntax.FormatPart::new(expression, literal))
    end_span = continuation.span()
    if last {
      break
    }
  }
  let span = self.cover(prefix.span(), end_span)
  self.node(span)
  Format(start~, parts~, span~)
}

///|
fn Parser::parse_value(self : Parser) -> @syntax.Expression raise ParserError {
  if self.accept(Bang) is Some(operator) {
    let operand = self.parse_value()
    let span = self.cover(operator.span(), operand.span())
    self.node(span)
    return Unary(operator=Not, operand~, span~)
  }
  if self.peek_keyword(If) {
    return self.parse_conditional()
  }
  let token = self.peek()
  match token.kind() {
    StringToken => {
      let literal = self.parse_plain_literal(StringToken)
      self.node(literal.span())
      String(literal)
    }
    Backtick => {
      let literal = self.parse_plain_literal(Backtick)
      if literal.cooked().has_prefix("#!") {
        raise BacktickShebang(span=literal.span())
      }
      self.node(literal.span())
      Backtick(literal)
    }
    BracketL => self.parse_list()
    ParenL => {
      let open = self.advance()
      let value = self.parse_expression_node()
      let close = self.expect(ParenR)
      let span = self.cover(open.span(), close.span())
      self.node(span)
      Parenthesized(expression=value, span~)
    }
    Identifier => {
      if self.shell_expanded_string_ahead() {
        let literal = self.parse_string_or_expanded_literal()
        let span = literal.span()
        self.node(span)
        return String(literal)
      }
      if self.lexeme(token) == "f" &&
        self.tokens.get(self.index + 1).map(t => t.kind())
        is Some(StringToken | FormatStringStart) {
        return self.parse_format()
      }
      let (name, name_token) = self.expect_identifier()
      if name == "true" || name == "false" {
        self.node(name_token.span())
        Boolean(value=name == "true", span=name_token.span())
      } else if self.peek_kind() == ParenL {
        self.parse_call(name, name_token.span())
      } else {
        self.node(name_token.span())
        Variable(name~, span=name_token.span())
      }
    }
    _ =>
      raise UnexpectedToken(
        expected=if self.parsing_parameter_default && token.kind() == Slash {
          "backtick, '!', '[', identifier, '(', or string"
        } else {
          "backtick, '!', '[', identifier, '(', '/', or string"
        },
        found=token.kind(),
        span=token.span(),
      )
  }
}

///|
/// Parse one expression from an existing token stream.
pub fn parse_expression_tokens(
  source : @source.Source,
  stream : @lexer.TokenStream,
  limits? : ParserLimits = ParserLimits::default(),
) -> @syntax.Expression raise ParserError {
  let parser = Parser::new(source, stream, limits)
  let expression = parser.parse_expression_node()
  if parser.peek_kind() != Eof &&
    parser.peek_kind() != Eol &&
    parser.peek_kind() != InterpolationEnd {
    raise ExtraneousInput(span=parser.peek().span())
  }
  expression
}

///|
/// Lex and parse one expression.
pub fn parse_expression(
  source : @source.Source,
  limits? : ParserLimits = ParserLimits::default(),
) -> @syntax.Expression raise ParserError {
  let stream = @lexer.lex(source) catch { error => raise LexerFailure(error) }
  parse_expression_tokens(source, stream, limits~)
}
