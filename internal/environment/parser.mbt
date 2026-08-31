///|
priv enum QuoteState {
  Plain
  Single
  Double
  EscapedPlain
  EscapedSingle
  EscapedDouble
  Comment
} derive(Eq)

///|
fn logical_lines(text : String) -> Array[(Int, String)] raise DotenvError {
  let result : Array[(Int, String)] = []
  let builder = StringBuilder()
  let mut state = Plain
  let mut whitespace = true
  let mut line = 1
  let mut start_line = 1
  for character in text {
    if character == '\r' && state != Single && state != Double {
      continue
    }
    if character == '\n' {
      match state {
        Single | EscapedSingle => {
          builder.write_char('\n')
          state = Single
        }
        Double | EscapedDouble => {
          builder.write_char('\n')
          state = Double
        }
        _ => {
          result.push((start_line, builder.to_string()))
          builder.reset()
          state = Plain
          whitespace = true
          start_line = line + 1
        }
      }
      line += 1
      continue
    }
    builder.write_char(character)
    state = match state {
      Comment => Comment
      EscapedPlain => Plain
      EscapedSingle => Single
      EscapedDouble => Double
      Single =>
        if character == '\\' {
          EscapedSingle
        } else if character == '\'' {
          Plain
        } else {
          Single
        }
      Double =>
        if character == '\\' {
          EscapedDouble
        } else if character == '"' {
          Plain
        } else {
          Double
        }
      Plain =>
        if character == '#' && whitespace {
          Comment
        } else if character == '\\' {
          EscapedPlain
        } else if character == '\'' {
          Single
        } else if character == '"' {
          Double
        } else {
          Plain
        }
    }
    whitespace = character == ' ' || character == '\t'
  }
  match state {
    Single | Double | EscapedSingle | EscapedDouble =>
      raise Parse(line=start_line, column=builder.to_string().length() + 1)
    _ => ()
  }
  if builder.to_string() != "" || text.has_suffix("\n") == false {
    result.push((start_line, builder.to_string()))
  }
  result
}

///|
fn skip_space(chars : Array[Char], start : Int) -> Int {
  let mut index = start
  while index < chars.length() && chars[index].is_whitespace() {
    index += 1
  }
  index
}

///|
fn valid_key_start(character : Char) -> Bool {
  character.is_ascii_alphabetic() || character == '_'
}

///|
fn valid_key_continue(character : Char) -> Bool {
  character.is_ascii_alphabetic() ||
  character.is_ascii_digit() ||
  character == '_' ||
  character == '.'
}

///|
fn parse_key(
  chars : Array[Char],
  start : Int,
  line : Int,
) -> (String, Int) raise DotenvError {
  if start >= chars.length() || !valid_key_start(chars[start]) {
    raise Parse(line~, column=start + 1)
  }
  let mut end = start + 1
  while end < chars.length() && valid_key_continue(chars[end]) {
    end += 1
  }
  (String::from_array(chars[start:end]), end)
}

///|
fn substitution(ambient : EnvTable, parsed : EnvTable, name : String) -> String {
  match ambient.get(name) {
    Some(value) => value
    None => parsed.get(name).unwrap_or("")
  }
}

///|
fn parse_value(
  chars : Array[Char],
  start : Int,
  line : Int,
  ambient : EnvTable,
  parsed : EnvTable,
) -> String raise DotenvError {
  let output = StringBuilder()
  let mut index = start
  let mut single = false
  let mut double = false
  let mut escaped = false
  let mut expecting_end = false
  while index < chars.length() {
    let character = chars[index]
    if expecting_end {
      if character == ' ' || character == '\t' {
        index += 1
        continue
      }
      if character == '#' {
        break
      }
      raise ParseValue(
        line~,
        column=index + 1,
        value=String::from_array(chars[start:]),
        index=index - start,
      )
    }
    if escaped {
      match character {
        '\\' | '\'' | '"' | '$' | ' ' => output.write_char(character)
        'n' => output.write_char('\n')
        _ => raise Parse(line~, column=index + 1)
      }
      escaped = false
      index += 1
      continue
    }
    if single {
      if character == '\'' {
        single = false
      } else {
        output.write_char(character)
      }
      index += 1
      continue
    }
    if character == '$' {
      let dollar = index
      index += 1
      if index < chars.length() && chars[index] == '{' {
        index += 1
        let name_start = index
        while index < chars.length() && chars[index] != '}' {
          index += 1
        }
        if index >= chars.length() {
          raise Parse(line~, column=chars.length())
        }
        let name = String::from_array(chars[name_start:index])
        output.write_string(substitution(ambient, parsed, name))
        index += 1
      } else {
        let name_start = index
        while index < chars.length() &&
              (
                chars[index].is_ascii_alphabetic() ||
                chars[index].is_ascii_digit()
              ) {
          index += 1
        }
        let name = String::from_array(chars[name_start:index])
        output.write_string(substitution(ambient, parsed, name))
        if index == dollar + 1 {
          continue
        }
      }
      continue
    }
    if double {
      if character == '"' {
        double = false
      } else if character == '\\' {
        escaped = true
      } else {
        output.write_char(character)
      }
    } else if character == '\'' {
      single = true
    } else if character == '"' {
      double = true
    } else if character == '\\' {
      escaped = true
    } else if character == ' ' || character == '\t' {
      expecting_end = true
    } else {
      output.write_char(character)
    }
    index += 1
  }
  if single || double {
    raise Parse(line~, column=chars.length())
  }
  output.to_string()
}

///|
fn parse_line(
  text : String,
  line : Int,
  ambient : EnvTable,
  parsed : EnvTable,
) -> Unit raise DotenvError {
  let chars = text.to_array()
  let mut index = skip_space(chars, 0)
  if index >= chars.length() || chars[index] == '#' {
    return
  }
  let first = parse_key(chars, index, line)
  let mut key = first.0
  index = skip_space(chars, first.1)
  if key == "export" && (index >= chars.length() || chars[index] != '=') {
    let next = parse_key(chars, index, line)
    key = next.0
    index = skip_space(chars, next.1)
  }
  if index >= chars.length() || chars[index] != '=' {
    raise Parse(line~, column=index + 1)
  }
  index = skip_space(chars, index + 1)
  if index >= chars.length() || chars[index] == '#' {
    parsed.set(key, "")
    return
  }
  parsed.set(key, parse_value(chars, index, line, ambient, parsed))
}

///|
/// Parse dotenvy-compatible text using an explicit ambient environment for
/// substitutions. Duplicate keys use the last parsed value, matching `just`.
pub fn parse_dotenv(
  text : String,
  ambient? : EnvTable = EnvTable::new(),
) -> EnvTable raise DotenvError {
  let parsed = EnvTable::new()
  for line in logical_lines(text) {
    parse_line(line.1, line.0, ambient, parsed)
  }
  parsed
}
