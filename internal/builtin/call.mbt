///|
/// Invoke one pure builtin with already evaluated arguments.
pub fn call(
  name : String,
  arguments : Array[Value],
) -> Value raise BuiltinError {
  let requested = name
  let name = canonical_name(name)
  match name {
    "absolute_path" | "canonicalize" | "clean" => {
      let path = path_value(name, one(name, arguments))
      String(path.as_string())
    }
    "append" => {
      let (suffix, collection) = two(name, arguments)
      let suffix = string_argument(name, suffix)
      match collection {
        List(values) => {
          let result : Array[Value] = []
          for value in values {
            result.push(String(string_argument(name, value) + suffix))
          }
          List(result)
        }
        _ => raise Type(name~, expected="list", actual=collection)
      }
    }
    "prepend" => {
      let (prefix, collection) = two(name, arguments)
      let prefix = string_argument(name, prefix)
      match collection {
        List(values) => {
          let result : Array[Value] = []
          for item in values {
            result.push(String(prefix + string_argument(name, item)))
          }
          List(result)
        }
        _ => raise Type(name~, expected="list", actual=collection)
      }
    }
    "bool" => Bool(one(name, arguments).truthy())
    "error" =>
      raise Failure(message=string_argument(name, one(name, arguments)))
    "capitalize" =>
      String(capitalize(string_argument(name, one(name, arguments))))
    "encode_uri_component" =>
      String(encode_uri_component(string_argument(name, one(name, arguments))))
    "file_stem" => {
      let raw = string_argument(name, one(name, arguments))
      let result = path_value(name, String(raw)).without_extension().file_name()
      match result {
        Some(value) => String(value)
        None =>
          raise Failure(
            message="could not extract file stem from `" + raw + "`",
          )
      }
    }
    "join_list" => {
      let collection = arguments[0]
      let separator = if arguments.length() == 2 {
        string_argument(name, arguments[1])
      } else {
        " "
      }
      String(collection.elements().join(separator))
    }
    "kebabcase" =>
      String(
        separated_case(string_argument(name, one(name, arguments)), '-', false),
      )
    "snakecase" =>
      String(
        separated_case(string_argument(name, one(name, arguments)), '_', false),
      )
    "shoutykebabcase" =>
      String(
        separated_case(string_argument(name, one(name, arguments)), '-', true),
      )
    "shoutysnakecase" =>
      String(
        separated_case(string_argument(name, one(name, arguments)), '_', true),
      )
    "titlecase" => {
      let words = case_words(string_argument(name, one(name, arguments)))
      let result : Array[String] = []
      for word in words {
        result.push(capitalize(lower_ascii(word)))
      }
      String(result.join(" "))
    }
    "lowercamelcase" | "uppercamelcase" => {
      let words = case_words(string_argument(name, one(name, arguments)))
      let result = StringBuilder()
      for index, word in words {
        if index == 0 && name == "lowercamelcase" {
          result.write_string(lower_ascii(word))
        } else {
          result.write_string(capitalize(lower_ascii(word)))
        }
      }
      String(result.to_string())
    }
    "len" => {
      let value = one(name, arguments)
      String(value.elements().length().to_string())
    }
    "parent_directory" => {
      let raw = string_argument(name, one(name, arguments))
      if raw.is_empty() {
        raise Failure(
          message="could not extract parent directory from `" + raw + "`",
        )
      }
      let path = path_value(name, String(raw))
      match path.parent() {
        Some(value) => String(value.as_string())
        None if !raw.contains("/") && !raw.contains("\\") => String(".")
        None =>
          raise Failure(
            message="could not extract parent directory from `" + raw + "`",
          )
      }
    }
    "split" => {
      let value = arguments[0]
      let value = string_argument(name, value)
      let separator = if arguments.length() == 2 {
        Some(string_argument(name, arguments[1]))
      } else {
        None
      }
      let result : Array[Value] = []
      match separator {
        None =>
          for item in whitespace_words(value) {
            result.push(String(item))
          }
        Some(separator) =>
          if separator == "" {
            for character in value {
              result.push(String(character.to_string()))
            }
          } else {
            for item in value.split(separator) {
              result.push(String("\{item}"))
            }
          }
      }
      List(result)
    }
    "show" => String(one(name, arguments).display())
    "style" => {
      if arguments.is_empty() {
        raise Arity(name~, expected="at least 1", actual=0)
      }
      String(arguments[arguments.length() - 1].to_string())
    }
    "trim_end" =>
      String(string_argument(name, one(name, arguments)).trim_end().to_owned())
    "trim_start" =>
      String(
        string_argument(name, one(name, arguments)).trim_start().to_owned(),
      )
    "trim_end_match"
    | "trim_start_match"
    | "trim_end_matches"
    | "trim_start_matches" => {
      let (value, match_value) = two(name, arguments)
      let value = string_argument(name, value)
      let match_value = string_argument(name, match_value)
      let mut result = value
      if match_value == "" {
        return String(result)
      }
      if name == "trim_end_match" {
        if result.has_suffix(match_value) {
          result = result
            .view(end_offset=result.length() - match_value.length())
            .to_owned()
        }
      } else if name == "trim_start_match" {
        if result.has_prefix(match_value) {
          result = result.view(start_offset=match_value.length()).to_owned()
        }
      } else if name == "trim_end_matches" {
        while result.has_suffix(match_value) {
          result = result
            .view(end_offset=result.length() - match_value.length())
            .to_owned()
        }
      } else {
        while result.has_prefix(match_value) {
          result = result.view(start_offset=match_value.length()).to_owned()
        }
      }
      String(result)
    }
    "join" => {
      if arguments.length() < 2 {
        raise Arity(
          name=requested,
          expected="at least 2",
          actual=arguments.length(),
        )
      }
      let mut path = path_value(requested, arguments[0])
      for value in arguments[1:] {
        let child = path_value(requested, value)
        path = path.join(child) catch {
          _ => raise InvalidPath(value=path.as_string())
        }
      }
      String(path.as_string())
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
      if old.is_empty() {
        let builder = StringBuilder()
        builder.write_string(replacement)
        for character in value {
          builder.write_char(character)
          builder.write_string(replacement)
        }
        String(builder.to_string())
      } else {
        String(value.split(old).join(replacement))
      }
    }
    "trim" =>
      String(string_argument(name, one(name, arguments)).trim().to_owned())
    "uppercase" =>
      String(upper_ascii(string_argument(name, one(name, arguments))))
    "lowercase" =>
      String(lower_ascii(string_argument(name, one(name, arguments))))
    "quote" => String(quote(string_argument(name, one(name, arguments))))
    "file_name" => {
      let raw = string_argument(name, one(name, arguments))
      match path_value(name, String(raw)).file_name() {
        Some(value) => String(value)
        None =>
          raise Failure(
            message="could not extract file name from `" + raw + "`",
          )
      }
    }
    "extension" => {
      let raw = string_argument(name, one(name, arguments))
      match path_value(name, String(raw)).extension() {
        Some(value) => String(value)
        None =>
          raise Failure(
            message="could not extract extension from `" + raw + "`",
          )
      }
    }
    "without_extension" => {
      let raw = string_argument(name, one(name, arguments))
      if raw.is_empty() {
        raise Failure(message="could not extract parent from `" + raw + "`")
      }
      String(path_value(name, String(raw)).without_extension().as_string())
    }
    "replace_regex" => {
      if arguments.length() != 2 && arguments.length() != 3 {
        raise Arity(name~, expected="2 or 3", actual=arguments.length())
      }
      let value = string_argument(name, arguments[0])
      let pattern = string_argument(name, arguments[1])
      if pattern.contains("\\1") ||
        pattern.contains("(?<=") ||
        pattern.contains("(?<!") {
        raise InvalidPattern(
          value=pattern,
          detail="invalid regular expression `" + pattern + "`",
        )
      }
      let regexp = @regexp.compile(pattern[:]) catch {
        error =>
          raise InvalidPattern(
            value=pattern,
            detail=regex_parse_failure(pattern, error),
          )
      }
      let result = regexp.execute(value[:])
      if arguments.length() == 2 {
        Bool(result.matched())
      } else if !result.matched() {
        String(value)
      } else {
        let replacement = string_argument(name, arguments[2])
        String(replace_regex_all(regexp, value, replacement))
      }
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
