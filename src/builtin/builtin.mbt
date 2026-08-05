///|
/// Names of pure builtins supported by the Phase 5 evaluator.
type Value = @value.Value

///|
pub fn names() -> ArrayView[String] {
  [
    "join", "replace", "trim", "uppercase", "lowercase", "quote", "path_join", "file_name",
    "extension", "stem", "regex_matches", "semver_matches", "sha256", "blake3",
  ][:]
}

///|
fn one(name : String, arguments : Array[Value]) -> Value raise BuiltinError {
  if arguments.length() != 1 {
    raise Arity(name~, expected="1", actual=arguments.length())
  }
  arguments[0]
}

///|
fn two(
  name : String,
  arguments : Array[Value],
) -> (Value, Value) raise BuiltinError {
  if arguments.length() != 2 {
    raise Arity(name~, expected="2", actual=arguments.length())
  }
  (arguments[0], arguments[1])
}

///|
fn string_argument(name : String, value : Value) -> String raise BuiltinError {
  match value.as_string() {
    Some(value) => value
    None => raise Type(name~, expected="string", actual=value.kind())
  }
}

///|
fn lower_ascii(value : String) -> String {
  let builder = StringBuilder()
  for character in value {
    if character.is_ascii_uppercase() {
      builder.write_char((character.to_int() + 32).to_char().unwrap())
    } else {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
fn upper_ascii(value : String) -> String {
  let builder = StringBuilder()
  for character in value {
    if character.is_ascii_lowercase() {
      builder.write_char((character.to_int() - 32).to_char().unwrap())
    } else {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
fn quote(value : String) -> String {
  "'" + value.replace(old="'", new="'\\''") + "'"
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

///|
fn numeric_version(value : String) -> Array[Int]? {
  let parts = value.split(".")
  let result : Array[Int] = []
  for part in parts {
    let digits = part.trim()
    if digits.is_empty() {
      return None
    }
    let mut number = 0
    for character in digits {
      if !character.is_ascii_digit() {
        return None
      }
      number = number * 10 + character.to_int() - 48
    }
    result.push(number)
  }
  Some(result)
}

///|
fn semver_matches(version : String, requirement : String) -> Bool {
  let value = numeric_version(version)
  match value {
    None => false
    Some(actual) => {
      let requirement = requirement.trim()
      if requirement == "" || requirement == "*" {
        return true
      }
      let (operator, raw) = if requirement.has_prefix(">=") {
        (">=", requirement.view(start_offset=2).to_owned())
      } else if requirement.has_prefix(">") {
        (">", requirement.view(start_offset=1).to_owned())
      } else if requirement.has_prefix("<=") {
        ("<=", requirement.view(start_offset=2).to_owned())
      } else if requirement.has_prefix("<") {
        ("<", requirement.view(start_offset=1).to_owned())
      } else if requirement.has_prefix("=") {
        ("=", requirement.view(start_offset=1).to_owned())
      } else {
        ("=", requirement.to_owned())
      }
      match numeric_version(raw) {
        None => false
        Some(expected) => {
          let length = Int::max(actual.length(), expected.length())
          let mut comparison = 0
          for index in 0..<length {
            let left = if index < actual.length() { actual[index] } else { 0 }
            let right = if index < expected.length() {
              expected[index]
            } else {
              0
            }
            if left < right {
              comparison = -1
              break
            }
            if left > right {
              comparison = 1
              break
            }
          }
          match operator {
            ">=" => comparison >= 0
            ">" => comparison > 0
            "<=" => comparison <= 0
            "<" => comparison < 0
            _ => comparison == 0
          }
        }
      }
    }
  }
}

///|
/// Invoke one pure builtin with already evaluated arguments.
pub fn call(
  name : String,
  arguments : Array[Value],
) -> Value raise BuiltinError {
  match name {
    "join" => {
      let (collection, separator) = two(name, arguments)
      let separator = string_argument(name, separator)
      match collection {
        List(_) =>
          String(
            collection.join(separator) catch {
              _ =>
                raise Type(
                  name~,
                  expected="list of strings",
                  actual="invalid list",
                )
            },
          )
        String(value) => String(value)
        Bool(_) => raise Type(name~, expected="list", actual=collection.kind())
      }
    }
    "replace" => {
      if arguments.length() != 3 {
        raise Arity(name~, expected="3", actual=arguments.length())
      }
      let value = arguments[0]
      let old = arguments[1]
      let replacement = arguments[2]
      let value = string_argument(name, value)
      let old = string_argument(name, old)
      let replacement = string_argument(name, replacement)
      String(value.replace(old~, new=replacement))
    }
    "trim" =>
      String(string_argument(name, one(name, arguments)).trim().to_owned())
    "uppercase" =>
      String(upper_ascii(string_argument(name, one(name, arguments))))
    "lowercase" =>
      String(lower_ascii(string_argument(name, one(name, arguments))))
    "quote" => String(quote(string_argument(name, one(name, arguments))))
    "path_join" => {
      if arguments.length() < 1 {
        raise Arity(name~, expected="at least 1", actual=0)
      }
      let mut path = path_value(name, arguments[0])
      for value in arguments[1:] {
        let child = path_value(name, value)
        path = path.join(child) catch {
          _ => raise InvalidPath(value=path.as_string())
        }
      }
      String(path.as_string())
    }
    "file_name" =>
      String(path_value(name, one(name, arguments)).file_name().unwrap_or(""))
    "extension" =>
      String(path_value(name, one(name, arguments)).extension().unwrap_or(""))
    "stem" =>
      String(
        path_value(name, one(name, arguments))
        .without_extension()
        .file_name()
        .unwrap_or(""),
      )
    "regex_matches" => {
      let (value, pattern) = two(name, arguments)
      let value = string_argument(name, value)
      let pattern = string_argument(name, pattern)
      let regexp = @regexp.compile(pattern[:]) catch {
        _ => raise InvalidPattern(value=pattern)
      }
      Bool(regexp.execute(value[:]).matched())
    }
    "semver_matches" => {
      let (version, requirement) = two(name, arguments)
      Bool(
        semver_matches(
          string_argument(name, version),
          string_argument(name, requirement),
        ),
      )
    }
    "sha256" => {
      let value = string_argument(name, one(name, arguments))
      String(sha256_bytes(@utf8.encode(value)))
    }
    "blake3" => {
      let value = string_argument(name, one(name, arguments))
      String(blake3_bytes(@utf8.encode(value)))
    }
    _ => raise Unknown(name~)
  }
}
