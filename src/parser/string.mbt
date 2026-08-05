///|
fn hex_value(character : Char) -> Int? {
  match character {
    '0'..='9' => Some(character.to_int() - '0'.to_int())
    'a'..='f' => Some(character.to_int() - 'a'.to_int() + 10)
    'A'..='F' => Some(character.to_int() - 'A'.to_int() + 10)
    _ => None
  }
}

///|
fn cook_string(text : String, span : @source.Span) -> String raise ParserError {
  let characters = text.to_array()
  let output = StringBuilder()
  let mut index = 0
  while index < characters.length() {
    let character = characters[index]
    if character != '\\' {
      output.write_char(character)
      index += 1
      continue
    }
    index += 1
    if index >= characters.length() {
      raise InvalidEscapeSequence(character="end-of-file", span~)
    }
    let escaped = characters[index]
    match escaped {
      'n' => output.write_char('\n')
      'r' => output.write_char('\r')
      't' => output.write_char('\t')
      '\\' => output.write_char('\\')
      '"' => output.write_char('"')
      '\n' => ()
      'u' => {
        index += 1
        if index >= characters.length() || characters[index] != '{' {
          raise InvalidUnicodeEscape(reason="expected `{`", span~)
        }
        index += 1
        let mut value = 0
        let mut digits = 0
        while index < characters.length() && characters[index] != '}' {
          guard hex_value(characters[index]) is Some(digit) else {
            raise InvalidUnicodeEscape(
              reason="expected hexadecimal digit",
              span~,
            )
          }
          value = value * 16 + digit
          digits += 1
          if digits > 6 {
            raise InvalidUnicodeEscape(
              reason="escape is longer than six digits",
              span~,
            )
          }
          index += 1
        }
        if digits == 0 {
          raise InvalidUnicodeEscape(reason="escape value is empty", span~)
        }
        if index >= characters.length() {
          raise InvalidUnicodeEscape(reason="unterminated escape", span~)
        }
        match value.to_char() {
          Some(value) => output.write_char(value)
          None =>
            raise InvalidUnicodeEscape(
              reason="code point is out of range",
              span~,
            )
        }
      }
      _ => raise InvalidEscapeSequence(character=escaped.to_string(), span~)
    }
    index += 1
  }
  output.to_string()
}

///|
fn literal_parts(raw : String) -> (@syntax.StringKind, Int, Bool) {
  if raw.has_prefix("\"\"\"") {
    (TripleCooked, 3, true)
  } else if raw.has_prefix("'''") {
    (TripleRaw, 3, false)
  } else if raw.has_prefix("\"") {
    (Cooked, 1, true)
  } else if raw.has_prefix("'") {
    (Raw, 1, false)
  } else {
    (Backtick, if raw.has_prefix("```") { 3 } else { 1 }, false)
  }
}

///|
fn slice_literal(raw : String, open : Int, close : Int) -> String {
  raw[open:raw.length() - close].to_owned()
}

///|
fn Parser::parse_plain_literal(
  self : Parser,
  expected : @lexer.TokenKind,
) -> @syntax.StringLiteral raise ParserError {
  let token = self.expect(expected)
  let raw = self.lexeme(token)
  let (kind, delimiter, cooked) = literal_parts(raw)
  let body = slice_literal(raw, delimiter, delimiter)
  let value = if cooked { cook_string(body, token.span()) } else { body }
  @syntax.StringLiteral::new(raw, value, kind, token.span())
}

///|
fn Parser::format_segment(
  self : Parser,
  token : @lexer.Token,
  first : Bool,
  last : Bool,
  kind : @syntax.StringKind,
  delimiter : Int,
) -> @syntax.StringLiteral raise ParserError {
  let raw = self.lexeme(token)
  let open = if first { delimiter } else { 2 }
  let close = if last { delimiter } else { 2 }
  let body = slice_literal(raw, open, close).replace(old="{{{{", new="{{")
  let cooked = match kind {
    Cooked | TripleCooked => cook_string(body, token.span())
    _ => body
  }
  @syntax.StringLiteral::new(raw, cooked, kind, token.span())
}
