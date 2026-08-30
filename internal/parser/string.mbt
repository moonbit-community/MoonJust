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
fn string_lines_inclusive(text : String) -> Array[String] {
  let result : Array[String] = []
  let mut start = 0
  for index in 0..<text.length() {
    if text.unsafe_get(index) == 10 {
      result.push(text[start:index + 1].to_owned())
      start = index + 1
    }
  }
  if start < text.length() {
    result.push(text[start:].to_owned())
  }
  result
}

///|
fn string_line_is_blank(line : String) -> Bool {
  line.all(fn(character) {
    character == ' ' ||
    character == '\t' ||
    character == '\r' ||
    character == '\n'
  })
}

///|
fn string_line_indentation(line : String) -> String {
  let mut length = 0
  while length < line.length() &&
        (line.unsafe_get(length) == 32 || line.unsafe_get(length) == 9) {
    length += 1
  }
  line[:length].to_owned()
}

///|
fn common_string_indentation(left : String, right : String) -> String {
  let mut length = 0
  while length < left.length() &&
        length < right.length() &&
        left.unsafe_get(length) == right.unsafe_get(length) {
    length += 1
  }
  left[:length].to_owned()
}

///|
pub fn unindent_string(text : String) -> String {
  let lines = string_lines_inclusive(text)
  let mut common : String? = None
  for line in lines {
    if string_line_is_blank(line) {
      continue
    }
    let indentation = string_line_indentation(line)
    common = Some(
      match common {
        Some(value) => common_string_indentation(value, indentation)
        None => indentation
      },
    )
  }
  let indentation = common.unwrap_or("")
  let output = StringBuilder()
  for index, line in lines {
    if string_line_is_blank(line) {
      if index != 0 && index + 1 != lines.length() {
        output.write_string(if line.has_suffix("\r\n") { "\r\n" } else { "\n" })
      }
    } else {
      output.write_string(
        line.view(start_offset=indentation.length()).to_owned(),
      )
    }
  }
  output.to_string()
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
      '\r' => {
        if index + 1 >= characters.length() || characters[index + 1] != '\n' {
          let error_span = @source.Span::new(
            span.source_id(),
            span.start_byte(),
            span.end_byte() - 1,
          ) catch {
            _ => span
          }
          raise InvalidEscapeSequence(character="\\r", span=error_span)
        }
        index += 1
      }
      'u' => {
        index += 1
        if index >= characters.length() || characters[index] != '{' {
          let found = if index < characters.length() {
            "`" + characters[index].to_string() + "`"
          } else {
            "end of file"
          }
          raise InvalidUnicodeEscape(
            reason="expected unicode escape sequence delimiter `{` but found " +
              found,
            span~,
          )
        }
        index += 1
        let mut value = 0
        let mut digits = 0
        let digit_text = StringBuilder()
        while index < characters.length() && characters[index] != '}' {
          guard hex_value(characters[index]) is Some(digit) else {
            raise InvalidUnicodeEscape(
              reason="expected hex digit [0-9A-Fa-f] but found `" +
                characters[index].to_string() +
                "`",
              span~,
            )
          }
          digit_text.write_char(characters[index])
          value = value * 16 + digit
          digits += 1
          if digits > 6 {
            raise InvalidUnicodeEscape(
              reason="unicode escape sequence starting with `\\u{" +
                digit_text.to_string() +
                "` longer than six hex digits",
              span~,
            )
          }
          index += 1
        }
        if digits == 0 {
          raise InvalidUnicodeEscape(
            reason="unicode escape sequences must not be empty",
            span~,
          )
        }
        if index >= characters.length() {
          raise InvalidUnicodeEscape(
            reason="unterminated unicode escape sequence",
            span~,
          )
        }
        match value.to_char() {
          Some(value) => output.write_char(value)
          None =>
            raise InvalidUnicodeEscape(
              reason="unicode escape sequence value `" +
                digit_text.to_string() +
                "` greater than maximum valid code point `10FFFF`",
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
fn shell_environment_value(
  environment : ArrayView[(String, String)],
  name : String,
) -> String? {
  for entry in environment {
    if entry.0 == name {
      return Some(entry.1)
    }
  }
  None
}

///|
fn shell_name_character(character : Char, first : Bool) -> Bool {
  character == '_' ||
  (if first {
    character.is_ascii_alphabetic()
  } else {
    character.is_ascii_alphabetic() || character.is_ascii_digit()
  })
}

///|
fn expand_shell_string(
  text : String,
  environment : ArrayView[(String, String)],
  span : @source.Span,
) -> String raise ParserError {
  let characters = text.to_array()
  let output = StringBuilder()
  let mut index = 0
  if !characters.is_empty() &&
    characters[0] == '~' &&
    (characters.length() == 1 || characters[1] == '/') {
    match shell_environment_value(environment, "HOME") {
      Some(home) => output.write_string(home)
      None => raise ShellExpansion(variable="HOME", span~)
    }
    index = 1
  }
  while index < characters.length() {
    if characters[index] != '$' {
      output.write_char(characters[index])
      index += 1
      continue
    }
    if index + 1 >= characters.length() {
      output.write_char('$')
      index += 1
      continue
    }
    let mut start = index + 1
    let mut end = start
    let mut braced = false
    if characters[start] == '{' {
      braced = true
      start += 1
      end = start
      while end < characters.length() && characters[end] != '}' {
        end += 1
      }
      if end >= characters.length() {
        output.write_char('$')
        index += 1
        continue
      }
    } else {
      while end < characters.length() &&
            shell_name_character(characters[end], end == start) {
        end += 1
      }
      if end == start {
        output.write_char('$')
        index += 1
        continue
      }
    }
    let name = String::from_array(characters[start:end])
    match shell_environment_value(environment, name) {
      Some(value) => output.write_string(value)
      None => raise ShellExpansion(variable=name, span~)
    }
    index = if braced { end + 1 } else { end }
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
  let raw_body = slice_literal(raw, delimiter, delimiter)
  let body = if delimiter == 3 { unindent_string(raw_body) } else { raw_body }
  let value = if cooked { cook_string(body, token.span()) } else { body }
  @syntax.StringLiteral::new(raw, value, kind, token.span())
}

///|
fn Parser::shell_expanded_string_ahead(self : Parser) -> Bool {
  let prefix = self.peek()
  prefix.kind() == Identifier &&
  self.lexeme(prefix) == "x" &&
  self.tokens.get(self.index + 1) is Some(string_token) &&
  string_token.kind() == StringToken &&
  prefix.span().end_byte() == string_token.span().start_byte()
}

///|
fn Parser::parse_string_or_expanded_literal(
  self : Parser,
) -> @syntax.StringLiteral raise ParserError {
  if !self.shell_expanded_string_ahead() {
    return self.parse_plain_literal(StringToken)
  }
  let prefix = self.advance()
  let literal = self.parse_plain_literal(StringToken)
  let span = self.cover(prefix.span(), literal.span())
  let expanded = expand_shell_string(
    literal.cooked(),
    self.environment,
    literal.span(),
  )
  @syntax.StringLiteral::new(
    "x" + literal.raw(),
    expanded,
    literal.kind(),
    span,
    shell_expanded=true,
  )
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
