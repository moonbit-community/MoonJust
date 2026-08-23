///|
priv struct StringKind {
  delimiter : Byte
  delimiter_length : Int
  cooked : Bool
  backtick : Bool
}

///|
fn Lexer::previous_token_is_format_prefix(self : Lexer) -> Bool {
  match self.tokens.last() {
    Some(token) if token.kind() == Identifier =>
      (try! token.lexeme(self.source)) == "f"
    _ => false
  }
}

///|
fn Lexer::top_format_kind(self : Lexer) -> StringKind? {
  match self.delimiters.last() {
    Some(frame) => frame.format
    None => None
  }
}

///|
fn Lexer::consume_count(self : Lexer, count : Int) -> Unit {
  for index = 0; index < count; index = index + 1 {
    self.take()
  }
}

///|
fn Lexer::starts_with_byte(self : Lexer, byte : Byte, count : Int) -> Bool {
  if self.offset + count > self.bytes.length() {
    return false
  }
  for index = 0; index < count; index = index + 1 {
    if self.bytes[self.offset + index] != byte {
      return false
    }
  }
  true
}

///|
fn Lexer::string_kind(self : Lexer) -> StringKind {
  let delimiter = self.peek(0)
  let delimiter_length = if self.starts_with_byte(delimiter, 3) { 3 } else { 1 }
  {
    delimiter,
    delimiter_length,
    cooked: delimiter == b'"',
    backtick: delimiter == b'`',
  }
}

///|
fn Lexer::take_scalar(self : Lexer) -> Unit {
  let byte = self.peek(0)
  if byte == b'\n' {
    self.line += 1
    self.column = 0
  } else {
    self.column += utf8_scalar_width(byte)
  }
  self.offset += utf8_scalar_width(byte)
}

///|
fn Lexer::lex_string_segment(
  self : Lexer,
  start : Int,
  kind : StringKind,
  format : Bool,
  resumed : Bool,
) -> Unit raise LexerError {
  self.consume_count(if resumed { 2 } else { kind.delimiter_length })
  let mut escaped = false
  while self.has(0) {
    let byte = self.peek(0)
    if format && self.starts_with_byte(b'{', 4) {
      escaped = false
      self.consume_count(4)
    } else if !escaped &&
      (
        self.starts_with_byte(kind.delimiter, kind.delimiter_length) ||
        (format && self.starts_with_byte(b'{', 2))
      ) {
      break
    } else if kind.cooked && !escaped && byte == b'\\' {
      escaped = true
      self.take()
    } else {
      // Upstream's lexer only protects escaped delimiters. Escape validity,
      // including Unicode escape syntax, belongs to the parser.
      escaped = false
      self.take_scalar()
    }
  }
  if !self.has(0) {
    let highlight = if resumed { 2 } else { kind.delimiter_length }
    let span = self.span(start, start + highlight)
    if kind.backtick {
      raise UnterminatedBacktick(span~)
    } else {
      raise UnterminatedString(span~)
    }
  }
  if format && self.starts_with_byte(b'{', 2) {
    self.consume_count(2)
    self.emit(
      if resumed {
        FormatStringContinue
      } else {
        FormatStringStart
      },
      start,
    )
    if !resumed {
      self.ensure_nesting(self.span(start, self.offset))
      self.delimiters.push({
        kind: FormatString,
        line: self.line,
        format: Some(kind),
      })
    }
  } else {
    self.consume_count(kind.delimiter_length)
    if resumed {
      self.delimiters.pop() |> ignore
      self.emit(FormatStringEnd, start)
    } else {
      self.emit(if kind.backtick { Backtick } else { StringToken }, start)
    }
  }
}

///|
fn Lexer::lex_string(self : Lexer, start : Int) -> Unit raise LexerError {
  let kind = self.string_kind()
  let format = !kind.backtick && self.previous_token_is_format_prefix()
  self.lex_string_segment(start, kind, format, false)
}

///|
fn Lexer::lex_format_resume(self : Lexer, start : Int) -> Unit raise LexerError {
  match self.top_format_kind() {
    Some(kind) => self.lex_string_segment(start, kind, true, true)
    None => ()
  }
}
