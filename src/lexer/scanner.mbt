///|
priv struct DelimiterFrame {
  kind : DelimiterKind
  line : Int
}

///|
priv struct Lexer {
  source : @source.Source
  bytes : BytesView
  mut offset : Int
  mut line : Int
  tokens : Array[Token]
  delimiters : Array[DelimiterFrame]
}

///|
fn Lexer::new(source : @source.Source) -> Lexer {
  {
    source,
    bytes: source.bytes(),
    offset: 0,
    line: 1,
    tokens: [],
    delimiters: [],
  }
}

///|
fn Lexer::span(self : Lexer, start : Int, end : Int) -> @source.Span {
  try! @source.Span::new(self.source.id(), start, end)
}

///|
fn Lexer::emit(self : Lexer, kind : TokenKind, start : Int) -> Unit {
  self.tokens.push(Token::new(kind, self.span(start, self.offset)))
}

///|
fn Lexer::emit_empty(self : Lexer, kind : TokenKind) -> Unit {
  self.tokens.push(Token::new(kind, self.span(self.offset, self.offset)))
}

///|
fn Lexer::has(self : Lexer, distance : Int) -> Bool {
  self.offset + distance < self.bytes.length()
}

///|
fn Lexer::peek(self : Lexer, distance : Int) -> Byte {
  self.bytes[self.offset + distance]
}

///|
fn Lexer::take(self : Lexer) -> Unit {
  self.offset += 1
}

///|
fn is_identifier_start(byte : Byte) -> Bool {
  (byte >= b'a' && byte <= b'z') ||
  (byte >= b'A' && byte <= b'Z') ||
  byte == b'_'
}

///|
fn is_identifier_continue(byte : Byte) -> Bool {
  is_identifier_start(byte) || (byte >= b'0' && byte <= b'9') || byte == b'-'
}

///|
fn utf8_scalar_width(byte : Byte) -> Int {
  if byte < 0x80 {
    1
  } else if byte < 0xe0 {
    2
  } else if byte < 0xf0 {
    3
  } else {
    4
  }
}

///|
fn Lexer::slice(self : Lexer, start : Int, end : Int) -> String {
  try! self.source.slice_text(self.span(start, end))
}

///|
fn Lexer::lex_identifier(self : Lexer, start : Int) -> Unit {
  self.take()
  while self.has(0) && is_identifier_continue(self.peek(0)) {
    self.take()
  }
  self.emit(Identifier, start)
}

///|
fn Lexer::lex_whitespace(self : Lexer, start : Int) -> Unit {
  while self.has(0) && (self.peek(0) == b' ' || self.peek(0) == b'\t') {
    self.take()
  }
  self.emit(Whitespace, start)
}

///|
fn Lexer::lex_comment(self : Lexer, start : Int) -> Unit {
  while self.has(0) && self.peek(0) != b'\n' && self.peek(0) != b'\r' {
    self.take()
  }
  self.emit(Comment, start)
}

///|
fn delimiter_for_open(byte : Byte) -> DelimiterKind {
  match byte {
    b'{' => Brace
    b'[' => Bracket
    _ => Paren
  }
}

///|
fn delimiter_for_close(byte : Byte) -> DelimiterKind {
  match byte {
    b'}' => Brace
    b']' => Bracket
    _ => Paren
  }
}

///|
fn token_for_open(byte : Byte) -> TokenKind {
  match byte {
    b'{' => BraceL
    b'[' => BracketL
    _ => ParenL
  }
}

///|
fn token_for_close(byte : Byte) -> TokenKind {
  match byte {
    b'}' => BraceR
    b']' => BracketR
    _ => ParenR
  }
}

///|
fn Lexer::lex_open(self : Lexer, start : Int) -> Unit {
  let byte = self.peek(0)
  self.delimiters.push({ kind: delimiter_for_open(byte), line: self.line })
  self.take()
  self.emit(token_for_open(byte), start)
}

///|
fn Lexer::lex_close(self : Lexer, start : Int) -> Unit raise LexerError {
  let byte = self.peek(0)
  let close = delimiter_for_close(byte)
  match self.delimiters.pop() {
    None =>
      raise UnexpectedClosingDelimiter(close~, span=self.span(start, start))
    Some(frame) if frame.kind != close =>
      raise MismatchedClosingDelimiter(
        open=frame.kind,
        close~,
        open_line=frame.line,
        span=self.span(start, start),
      )
    Some(_) => ()
  }
  self.take()
  self.emit(token_for_close(byte), start)
}

///|
fn Lexer::lex_digraph(
  self : Lexer,
  start : Int,
  second : Byte,
  kind : TokenKind,
) -> Unit raise LexerError {
  self.take()
  if !self.has(0) {
    raise UnexpectedEndOfToken(
      expected=self.slice(start, start + 1),
      span=self.span(self.offset, self.offset),
    )
  }
  if self.peek(0) != second {
    let unexpected_start = self.offset
    let width = utf8_scalar_width(self.peek(0))
    let found = self.slice(unexpected_start, unexpected_start + width)
    raise UnexpectedCharacter(
      expected=self.slice(start, start + 1),
      found~,
      span=self.span(unexpected_start, unexpected_start + width),
    )
  }
  self.take()
  self.emit(kind, start)
}

///|
fn Lexer::lex_escape(self : Lexer, start : Int) -> Unit raise LexerError {
  self.take()
  if !self.has(0) {
    raise EscapeEndOfFile(span=self.span(start, self.offset))
  }
  if self.peek(0) == b'\n' {
    self.take()
    self.line += 1
  } else if self.peek(0) == b'\r' {
    self.take()
    if !self.has(0) || self.peek(0) != b'\n' {
      raise UnpairedCarriageReturn(span=self.span(self.offset - 1, self.offset))
    }
    self.take()
    self.line += 1
  } else {
    let width = utf8_scalar_width(self.peek(0))
    raise InvalidEscapeSequence(
      character=self.slice(self.offset, self.offset + width),
      span=self.span(self.offset, self.offset + width),
    )
  }
  while self.has(0) && (self.peek(0) == b' ' || self.peek(0) == b'\t') {
    self.take()
  }
  self.emit(Whitespace, start)
}

///|
fn Lexer::lex_eol(self : Lexer, start : Int) -> Unit raise LexerError {
  if self.peek(0) == b'\r' {
    self.take()
    if !self.has(0) || self.peek(0) != b'\n' {
      raise UnpairedCarriageReturn(span=self.span(start, self.offset))
    }
  }
  self.take()
  self.line += 1
  self.emit(if self.delimiters.is_empty() { Eol } else { Whitespace }, start)
}

///|
fn Lexer::lex_choice(
  self : Lexer,
  start : Int,
  second : Byte,
  double : TokenKind,
  single : TokenKind,
) -> Unit {
  self.take()
  if self.has(0) && self.peek(0) == second {
    self.take()
    self.emit(double, start)
  } else {
    self.emit(single, start)
  }
}

///|
fn Lexer::lex_normal(self : Lexer) -> Unit raise LexerError {
  let start = self.offset
  let byte = self.peek(0)
  if is_identifier_start(byte) {
    self.lex_identifier(start)
  } else {
    match byte {
      b' ' | b'\t' => self.lex_whitespace(start)
      b'#' => self.lex_comment(start)
      b'\n' | b'\r' => self.lex_eol(start)
      b'{' | b'[' | b'(' => self.lex_open(start)
      b'}' | b']' | b')' => self.lex_close(start)
      b'&' => self.lex_digraph(start, b'&', AmpersandAmpersand)
      b'|' => self.lex_digraph(start, b'|', BarBar)
      b'!' => {
        self.take()
        if self.has(0) && self.peek(0) == b'=' {
          self.take()
          self.emit(BangEquals, start)
        } else if self.has(0) && self.peek(0) == b'~' {
          self.take()
          self.emit(BangTilde, start)
        } else {
          self.emit(Bang, start)
        }
      }
      b'+' => self.lex_choice(start, b'+', PlusPlus, Plus)
      b'=' => {
        self.take()
        if self.has(0) && self.peek(0) == b'=' {
          self.take()
          self.emit(EqualsEquals, start)
        } else if self.has(0) && self.peek(0) == b'~' {
          self.take()
          self.emit(EqualsTilde, start)
        } else {
          self.emit(Equals, start)
        }
      }
      b':' => {
        self.take()
        if self.has(0) && self.peek(0) == b'=' {
          self.take()
          self.emit(ColonEquals, start)
        } else if self.has(0) && self.peek(0) == b':' {
          self.take()
          self.emit(ColonColon, start)
        } else {
          self.emit(Colon, start)
        }
      }
      b'\\' => self.lex_escape(start)
      b'*' => {
        self.take()
        self.emit(Asterisk, start)
      }
      b'@' => {
        self.take()
        self.emit(At, start)
      }
      b',' => {
        self.take()
        self.emit(Comma, start)
      }
      b'$' => {
        self.take()
        self.emit(Dollar, start)
      }
      b'?' => {
        self.take()
        self.emit(QuestionMark, start)
      }
      b'/' => {
        self.take()
        self.emit(Slash, start)
      }
      0xef =>
        if self.has(2) && self.peek(1) == 0xbb && self.peek(2) == 0xbf {
          self.offset += 3
          self.emit(ByteOrderMark, start)
        } else {
          let width = utf8_scalar_width(byte)
          raise UnknownStartOfToken(
            start=self.slice(start, start + width),
            span=self.span(start, start + width),
          )
        }
      _ => {
        let width = utf8_scalar_width(byte)
        raise UnknownStartOfToken(
          start=self.slice(start, start + width),
          span=self.span(start, start + width),
        )
      }
    }
  }
}

///|
fn Lexer::run(self : Lexer) -> TokenStream raise LexerError {
  while self.offset < self.bytes.length() {
    self.lex_normal()
  }
  self.emit_empty(Eof)
  { source_id: self.source.id(), tokens: self.tokens }
}

///|
/// Lex a validated UTF-8 source using the default compatibility behavior.
pub fn lex(source : @source.Source) -> TokenStream raise LexerError {
  Lexer::new(source).run()
}
