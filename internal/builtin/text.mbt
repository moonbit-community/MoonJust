///|
fn compile_regex(pattern : String) -> @regexp.Regexp raise BuiltinError {
  if pattern.contains("\\1") ||
    pattern.contains("(?<=") ||
    pattern.contains("(?<!") {
    raise InvalidPattern(
      value=pattern,
      detail="invalid regular expression `" + pattern + "`",
    )
  }
  @regexp.compile(pattern[:]) catch {
    error =>
      raise InvalidPattern(
        value=pattern,
        detail=regex_parse_failure(pattern, error),
      )
  }
}

///|
pub fn regex_matches(
  value : String,
  pattern : String,
) -> Bool raise BuiltinError {
  compile_regex(pattern).execute(value[:]).matched()
}

///|
fn replacement_name_character(character : Char) -> Bool {
  character.is_ascii_lowercase() ||
  character.is_ascii_uppercase() ||
  character.is_ascii_digit() ||
  character == '_'
}

///|
fn replacement_capture_index(regexp : @regexp.Regexp, name : String) -> Int32? {
  if name == "" {
    return None
  }
  let mut numeric = true
  let mut value = 0
  for character in name {
    if !character.is_ascii_digit() {
      numeric = false
      break
    }
    value = value * 10 + character.to_int() - '0'.to_int()
  }
  if numeric {
    Some(value)
  } else {
    regexp.group_by_name(name)
  }
}

///|
fn write_replacement(
  regexp : @regexp.Regexp,
  result : @regexp.MatchResult,
  matched : StringView,
  replacement : String,
  builder : StringBuilder,
) -> Unit {
  let characters = replacement.to_array()
  let mut index = 0
  while index < characters.length() {
    if characters[index] != '$' || index + 1 >= characters.length() {
      builder.write_char(characters[index])
      index += 1
      continue
    }
    let next = characters[index + 1]
    if next == '$' {
      builder.write_char('$')
      index += 2
      continue
    }
    let mut end = index + 1
    if next == '{' {
      end += 1
      let start = end
      while end < characters.length() && characters[end] != '}' {
        end += 1
      }
      if end >= characters.length() {
        builder.write_char('$')
        index += 1
        continue
      }
      let name = String::from_array(characters[start:end])
      match replacement_capture_index(regexp, name) {
        Some(capture) =>
          match
            (if capture == 0 { Some(matched) } else { result.get(capture) }) {
            Some(value) => builder.write_stringview(value)
            None => ()
          }
        None => ()
      }
      index = end + 1
      continue
    }
    while end < characters.length() &&
          replacement_name_character(characters[end]) {
      end += 1
    }
    if end == index + 1 {
      builder.write_char('$')
      index += 1
      continue
    }
    let name = String::from_array(characters[index + 1:end])
    match replacement_capture_index(regexp, name) {
      Some(capture) =>
        match (if capture == 0 { Some(matched) } else { result.get(capture) }) {
          Some(value) => builder.write_stringview(value)
          None => ()
        }
      None => ()
    }
    index = end
  }
}

///|
fn replace_regex_all(
  regexp : @regexp.Regexp,
  pattern : String,
  value : String,
  replacement : String,
) -> String raise BuiltinError {
  let builder = StringBuilder()
  let mut resumed : @regexp.Regexp? = None
  let mut search = 0
  let mut previous_end = -1
  let mut copied = 0
  while search <= value.length() {
    let result = if search == 0 {
      regexp.execute(value[:])
    } else {
      let engine = match resumed {
        Some(engine) => engine
        None => {
          let engine = @regexp.compile("(?s:.)(?:" + pattern + ")") catch {
            error =>
              raise InvalidPattern(
                value=pattern,
                detail=regex_parse_failure(pattern, error),
              )
          }
          resumed = Some(engine)
          engine
        }
      }
      let previous = value.offset_of_nth_char(-1, end=search).unwrap()
      engine.execute(value[previous:])
    }
    guard result.get(0) is Some(full) else { break }
    let matched = if search == 0 {
      full
    } else {
      full[full.offset_of_nth_char(1).unwrap_or(full.length()):]
    }
    let start = matched.start_offset()
    let end = start + matched.length()
    if start != end || end != previous_end {
      builder.write_stringview(value[copied:start])
      write_replacement(regexp, result, matched, replacement, builder)
      copied = end
      previous_end = end
    }
    if start == end {
      if end == value.length() {
        break
      }
      search = value.offset_of_nth_char(1, start=end).unwrap_or(value.length())
    } else {
      search = end
    }
  }
  builder.write_stringview(value[copied:])
  builder.to_string()
}

///|
fn quote(value : String) -> String {
  "'" + value.replace_all(old="'", new="'\\''") + "'"
}

///|
fn capitalize(value : String) -> String {
  let builder = StringBuilder()
  for index, character in value {
    if index == 0 {
      builder.write_string(@unicode.to_uppercase(character))
    } else {
      builder.write_string(@unicode.to_lowercase(character))
    }
  }
  builder.to_string()
}

///|
fn case_words(value : String) -> Array[String] {
  let chars = value.to_array()
  let words = []
  let mut start = 0
  let mut last_upper : Bool? = None
  for index, c in chars {
    if !@unicode.is_alphabetic(c) &&
      !(@unicode.general_category(c) is (Nd | Nl | No)) {
      if start < index {
        words.push(String::from_array(chars[start:index]))
      }
      start = index + 1
      last_upper = None
    } else if @unicode.is_uppercase(c) {
      let ends_acronym = last_upper == Some(true) &&
        index + 1 < chars.length() &&
        @unicode.is_lowercase(chars[index + 1])
      if last_upper == Some(false) || ends_acronym {
        words.push(String::from_array(chars[start:index]))
        start = index
      }
      last_upper = Some(true)
    } else if @unicode.is_lowercase(c) {
      last_upper = Some(false)
    }
  }
  if start < chars.length() {
    words.push(String::from_array(chars[start:]))
  }
  words
}

///|
fn case_word(word : String, capitalized~ : Bool = false) -> String {
  let output = StringBuilder()
  let chars = word.to_array()
  for i, c in chars {
    output.write_string(
      if capitalized && i == 0 {
        @unicode.to_uppercase(c)
      } else if c == 'Σ' && i + 1 == chars.length() {
        "ς"
      } else {
        @unicode.to_lowercase(c)
      },
    )
  }
  output.to_string()
}

///|
fn separated_case(value : String, separator : Char, upper : Bool) -> String {
  let words = case_words(value)
  let result : Array[String] = []
  for word in words {
    result.push(if upper { @unicode.uppercase(word) } else { case_word(word) })
  }
  result.join(separator.to_string())
}

///|
fn whitespace_words(value : String) -> Array[String] {
  let words : Array[String] = []
  let mut current = StringBuilder()
  for character in value {
    if @unicode.is_white_space(character) {
      if !current.is_empty() {
        words.push(current.to_string())
        current = StringBuilder()
      }
    } else {
      current.write_char(character)
    }
  }
  if !current.is_empty() {
    words.push(current.to_string())
  }
  words
}

///|
fn encode_uri_component(value : String) -> String {
  let builder = StringBuilder()
  let digits = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
  ]
  for byte in @utf8.encode(value) {
    let code = byte.to_int()
    if (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code == 45 ||
      code == 46 ||
      code == 95 ||
      code == 126 ||
      code == 33 ||
      code == 42 ||
      code == 39 ||
      code == 40 ||
      code == 41 {
      builder.write_char(code.to_char().unwrap())
    } else {
      builder.write_char('%')
      builder.write_char(digits[(code >> 4) & 15])
      builder.write_char(digits[code & 15])
    }
  }
  builder.to_string()
}

///|
fn path_value(
  name : String,
  value : Value,
) -> @path.PathValue raise BuiltinError {
  let text = string_argument(name, value)
  @path.PathValue::new(text, Unix) catch {
    _ => raise InvalidPath(value=text)
  }
}
