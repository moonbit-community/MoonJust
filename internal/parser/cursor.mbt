///|
priv struct Parser {
  source : @source.Source
  tokens : Array[@lexer.Token]
  mut index : Int
  limits : ParserLimits
  environment : Array[(String, String)]
  mut depth : Int
  mut nodes : Int
  mut parsing_parameter_default : Bool
}

///|
fn Parser::new(
  source : @source.Source,
  stream : @lexer.TokenStream,
  limits : ParserLimits,
  environment? : ArrayView[(String, String)] = [],
) -> Parser {
  {
    source,
    tokens: stream.tokens().to_owned(),
    index: 0,
    limits,
    environment: environment.to_owned(),
    depth: 0,
    nodes: 0,
    parsing_parameter_default: false,
  }
}

///|
fn Parser::skip_whitespace(self : Parser) -> Unit {
  while self.index < self.tokens.length() &&
        self.tokens[self.index].kind() == Whitespace {
    self.index += 1
  }
}

///|
fn Parser::peek(self : Parser) -> @lexer.Token {
  self.skip_whitespace()
  if self.index < self.tokens.length() {
    self.tokens[self.index]
  } else {
    self.tokens[self.tokens.length() - 1]
  }
}

///|
fn Parser::peek_kind(self : Parser) -> @lexer.TokenKind {
  self.peek().kind()
}

///|
fn Parser::peek_kind_at(self : Parser, offset : Int) -> @lexer.TokenKind? {
  let mut cursor = self.index
  let mut seen = 0
  while cursor < self.tokens.length() {
    let kind = self.tokens[cursor].kind()
    cursor += 1
    if kind == Whitespace {
      continue
    }
    if seen == offset {
      return Some(kind)
    }
    seen += 1
  }
  None
}

///|
fn Parser::lexeme(self : Parser, token : @lexer.Token) -> String {
  try! token.lexeme(self.source)
}

///|
fn Parser::peek_keyword(self : Parser, keyword : @lexer.Keyword) -> Bool {
  let token = self.peek()
  token.kind() == Identifier && self.lexeme(token) == keyword.lexeme()
}

///|
fn Parser::advance(self : Parser) -> @lexer.Token {
  self.skip_whitespace()
  let token = self.peek()
  if self.index < self.tokens.length() {
    self.index += 1
  }
  token
}

///|
fn Parser::accept(self : Parser, kind : @lexer.TokenKind) -> @lexer.Token? {
  if self.peek_kind() == kind {
    Some(self.advance())
  } else {
    None
  }
}

///|
fn Parser::accept_keyword(
  self : Parser,
  keyword : @lexer.Keyword,
) -> @lexer.Token? {
  if self.peek_keyword(keyword) {
    Some(self.advance())
  } else {
    None
  }
}

///|
fn Parser::line_finished(self : Parser) -> Bool {
  match self.peek_kind() {
    Eol | Eof | Dedent | Comment => true
    _ => false
  }
}

///|
fn Parser::consume_line_end(self : Parser) -> Unit raise ParserError {
  self.consume_line_end_expected("end-of-line")
}

///|
fn Parser::consume_line_end_expected(
  self : Parser,
  expected : String,
) -> Unit raise ParserError {
  self.accept(Comment) |> ignore
  if self.peek_kind() == Eol {
    self.advance() |> ignore
  } else if !self.line_finished() {
    let found = self.peek()
    raise UnexpectedToken(expected~, found=found.kind(), span=found.span())
  }
}

///|
fn Parser::expect(
  self : Parser,
  kind : @lexer.TokenKind,
) -> @lexer.Token raise ParserError {
  match self.accept(kind) {
    Some(token) => token
    None => {
      let found = self.peek()
      raise UnexpectedToken(
        expected=kind.as_string(),
        found=found.kind(),
        span=found.span(),
      )
    }
  }
}

///|
fn Parser::expect_identifier(
  self : Parser,
) -> (String, @lexer.Token) raise ParserError {
  let token = self.expect(Identifier)
  (self.lexeme(token), token)
}

///|
fn Parser::span(self : Parser, start : Int, end : Int) -> @source.Span {
  try! @source.Span::new(self.source.id(), start, end)
}

///|
fn Parser::cover(
  self : Parser,
  first : @source.Span,
  last : @source.Span,
) -> @source.Span {
  self.span(first.start_byte(), last.end_byte())
}

///|
fn Parser::enter(self : Parser) -> Unit raise ParserError {
  if self.depth >= self.limits.max_depth() {
    raise RecursionLimitExceeded(
      limit=self.limits.max_depth(),
      span=self.peek().span(),
    )
  }
  self.depth += 1
}

///|
fn Parser::leave(self : Parser) -> Unit {
  self.depth -= 1
}

///|
fn Parser::node(self : Parser, span : @source.Span) -> Unit raise ParserError {
  if self.nodes >= self.limits.max_nodes() {
    raise NodeLimitExceeded(limit=self.limits.max_nodes(), span~)
  }
  self.nodes += 1
}
