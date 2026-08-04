///|
fn contains_space(text : String) -> Bool {
  text.contains(" ")
}

///|
fn contains_tab(text : String) -> Bool {
  text.contains("\t")
}

///|
fn Lexer::current_indentation(self : Lexer) -> String {
  self.indentation[self.indentation.length() - 1]
}

///|
fn Lexer::consume_leading(self : Lexer, count : Int, kind : TokenKind) -> Unit {
  let start = self.offset
  for index = 0; index < count; index = index + 1 {
    self.take()
  }
  if count > 0 || kind == Indent {
    self.emit(kind, start)
  }
}

///|
fn Lexer::emit_dedent(self : Lexer) -> Unit {
  self.indentation.pop() |> ignore
  self.emit_empty(Dedent)
  if self.indentation.length() == 1 {
    self.recipe_body = false
  }
}

///|
fn Lexer::blank_sequence_reaches_unindented_line(self : Lexer) -> Bool {
  let mut cursor = self.offset
  while cursor < self.bytes.length() {
    while cursor < self.bytes.length() &&
          (self.bytes[cursor] == b' ' || self.bytes[cursor] == b'\t') {
      cursor += 1
    }
    if cursor >= self.bytes.length() {
      return false
    }
    if self.bytes[cursor] == b'\r' &&
      cursor + 1 < self.bytes.length() &&
      self.bytes[cursor + 1] == b'\n' {
      cursor += 2
    } else if self.bytes[cursor] == b'\n' {
      cursor += 1
    } else {
      return false
    }
    if cursor >= self.bytes.length() {
      return false
    }
    if self.bytes[cursor] != b' ' &&
      self.bytes[cursor] != b'\t' &&
      self.bytes[cursor] != b'\r' &&
      self.bytes[cursor] != b'\n' {
      return true
    }
  }
  false
}

///|
fn Lexer::lex_line_start(self : Lexer) -> Unit raise LexerError {
  let start = self.offset
  let mut whitespace_end = start
  while whitespace_end < self.bytes.length() &&
        (
          self.bytes[whitespace_end] == b' ' ||
          self.bytes[whitespace_end] == b'\t'
        ) {
    whitespace_end += 1
  }
  let whitespace = self.slice(start, whitespace_end)

  if !self.delimiters.is_empty() || !self.interpolations.is_empty() {
    self.consume_leading(whitespace_end - start, Whitespace)
    return
  }

  let blank = whitespace_end == self.bytes.length() ||
    self.bytes[whitespace_end] == b'\n' ||
    (
      self.bytes[whitespace_end] == b'\r' &&
      whitespace_end + 1 < self.bytes.length() &&
      self.bytes[whitespace_end + 1] == b'\n'
    )
  if blank {
    if self.indentation.length() > 1 &&
      self.blank_sequence_reaches_unindented_line() {
      while self.indentation.length() > 1 {
        self.emit_dedent()
      }
    }
    self.consume_leading(whitespace_end - start, Whitespace)
    return
  }

  let current = self.current_indentation()
  let current_length = current.length()
  let body_length = Int::min(whitespace.length(), current_length)
  let body_whitespace = self.slice(start, start + body_length)
  let spaces = contains_space(whitespace)
  let tabs = contains_tab(whitespace)
  let body_spaces = contains_space(body_whitespace)
  let body_tabs = contains_tab(body_whitespace)

  if whitespace == current {
    self.consume_leading(whitespace.length(), Whitespace)
  } else if self.indentation.contains(whitespace) {
    while self.current_indentation() != whitespace {
      self.emit_dedent()
    }
    self.consume_leading(whitespace.length(), Whitespace)
  } else if self.recipe_body && whitespace.has_prefix(current) {
    self.consume_leading(current_length, Whitespace)
  } else if self.recipe_body && body_spaces && body_tabs {
    self.consume_leading(body_length, Whitespace)
    raise MixedLeadingWhitespace(
      whitespace=body_whitespace,
      span=self.span(start, start + body_length),
    )
  } else if !self.recipe_body && spaces && tabs {
    self.consume_leading(whitespace.length(), Whitespace)
    raise MixedLeadingWhitespace(
      whitespace~,
      span=self.span(start, whitespace_end),
    )
  } else if whitespace.length() < current_length ||
    (whitespace.length() >= current_length && !whitespace.has_prefix(current)) {
    self.consume_leading(whitespace.length(), Whitespace)
    raise InconsistentLeadingWhitespace(
      expected=current,
      found=whitespace,
      span=self.span(start, whitespace_end),
    )
  } else {
    self.consume_leading(whitespace.length(), Indent)
    self.indentation.push(whitespace)
    self.recipe_body = self.recipe_body_pending
    self.recipe_body_pending = false
  }
}
