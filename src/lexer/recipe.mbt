///|
fn Lexer::starts_with_pair(self : Lexer, first : Byte, second : Byte) -> Bool {
  self.has(1) && self.peek(0) == first && self.peek(1) == second
}

///|
fn Lexer::lex_body(self : Lexer) -> Unit raise LexerError {
  let start = self.offset
  while self.has(0) {
    if self.peek(0) == b'\n' ||
      (self.peek(0) == b'\r' && self.has(1) && self.peek(1) == b'\n') ||
      self.starts_with_pair(b'{', b'{') {
      if self.starts_with_byte(b'{', 4) {
        self.consume_count(4)
        continue
      }
      break
    }
    self.take_scalar()
  }
  if self.offset > start {
    self.emit(Text, start)
  } else if self.starts_with_pair(b'{', b'{') {
    let opening_span = self.span(start, start + 2)
    self.ensure_nesting(opening_span)
    self.consume_count(2)
    self.emit(InterpolationStart, start)
    self.interpolations.push(opening_span)
  } else if self.has(0) {
    self.lex_eol(start)
  }
}

///|
fn Lexer::lex_interpolation(self : Lexer) -> Unit raise LexerError {
  if self.starts_with_pair(b'}', b'}') && self.delimiters.is_empty() {
    let start = self.offset
    self.consume_count(2)
    self.emit(InterpolationEnd, start)
    self.interpolations.pop() |> ignore
  } else {
    self.lex_normal()
  }
}
