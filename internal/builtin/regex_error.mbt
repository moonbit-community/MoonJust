///|
fn regex_unclosed_group_index(pattern : String) -> Int {
  let open : Array[Int] = []
  let mut escaped = false
  for index, character in pattern.to_array() {
    if escaped {
      escaped = false
    } else if character == '\\' {
      escaped = true
    } else if character == '(' {
      open.push(index)
    } else if character == ')' && !open.is_empty() {
      ignore(open.pop())
    }
  }
  open.last().unwrap_or(0)
}

///|
fn regex_repeat_index(pattern : String) -> Int {
  let characters = pattern.to_array()
  for index, character in characters {
    if character == '{' ||
      character == '*' ||
      character == '+' ||
      character == '?' {
      return index
    }
  }
  0
}

///|
fn regex_error_index(
  pattern : String,
  error : @regexp.Err,
  source_fragment : StringView,
) -> Int {
  match error {
    MissingParenthesis => regex_unclosed_group_index(pattern)
    TrailingBackslash => Int::max(pattern.to_array().length() - 1, 0)
    MissingRepeatArgument => regex_repeat_index(pattern)
    _ => {
      let consumed = pattern.length() - source_fragment.length()
      let prefix = pattern[:Int::max(consumed, 0)]
      prefix.to_array().length()
    }
  }
}

///|
fn regex_error_description(pattern : String, error : @regexp.Err) -> String {
  if pattern.to_array().get(0) is Some('{' | '*' | '+' | '?') {
    return "repetition operator missing expression"
  }
  match error {
    MissingParenthesis => "unclosed group"
    TrailingBackslash =>
      "incomplete escape sequence, reached end of pattern prematurely"
    MissingRepeatArgument => "repetition operator missing expression"
    UnexpectedParenthesis => "unopened group"
    MissingBracket => "unclosed character class"
    InvalidEscape => "invalid escape sequence"
    InvalidRepeatOp => "invalid repetition operator"
    InvalidRepeatSize => "invalid repetition count"
    InvalidCharClass => "invalid character class"
    InvalidNamedCapture => "invalid capture group name"
    InternalError => "invalid regular expression"
  }
}

///|
/// Render a regexp parser failure using the diagnostic shape exposed by just.
pub fn regex_parse_failure(
  pattern : String,
  error : @regexp.RegexpError,
) -> String {
  let (kind, fragment) = match error {
    RegexpError(err~, source_fragment~) => (err, source_fragment)
  }
  let index = regex_error_index(pattern, kind, fragment)
  "regex parse error:\n    " +
  pattern +
  "\n    " +
  " ".repeat(index) +
  "^\nerror: " +
  regex_error_description(pattern, kind)
}
