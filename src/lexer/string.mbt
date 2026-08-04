///|
priv struct StringKind {
  delimiter : Byte
  delimiter_length : Int
  cooked : Bool
  backtick : Bool
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
  }
  self.offset += utf8_scalar_width(byte)
}

///|
fn Lexer::lex_string(self : Lexer, start : Int) -> Unit raise LexerError {
  let kind = self.string_kind()
  self.offset += kind.delimiter_length
  let mut escaped = false
  while self.has(0) {
    if !escaped && self.starts_with_byte(kind.delimiter, kind.delimiter_length) {
      self.offset += kind.delimiter_length
      self.emit(if kind.backtick { Backtick } else { StringToken }, start)
      return
    }
    let byte = self.peek(0)
    if kind.cooked && !escaped && byte == b'\\' {
      escaped = true
      self.take()
    } else {
      // Upstream's lexer only protects escaped delimiters. Escape validity,
      // including Unicode escape syntax, belongs to the parser.
      escaped = false
      self.take_scalar()
    }
  }
  let span = self.span(start, start + kind.delimiter_length)
  if kind.backtick {
    raise UnterminatedBacktick(span~)
  } else {
    raise UnterminatedString(span~)
  }
}
