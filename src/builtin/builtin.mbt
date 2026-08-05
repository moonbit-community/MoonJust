///|
/// Names of pure builtins supported by the Phase 5 evaluator.
type Value = @value.Value

///|
pub(all) enum BuiltinPurity {
  Pure
  Effect
} derive(Eq, Debug)

///|
pub(all) struct BuiltinSpec {
  name : String
  purity : BuiltinPurity
} derive(Eq, Debug)

///|
pub fn BuiltinSpec::name(self : BuiltinSpec) -> String {
  self.name
}

///|
pub fn BuiltinSpec::purity(self : BuiltinSpec) -> BuiltinPurity {
  self.purity
}

///|
pub fn names() -> ArrayView[String] {
  [
    "absolute_path", "append", "arch", "blake3", "blake3_file", "bool", "cache_directory",
    "canonicalize", "capitalize", "choose", "clean", "config_directory", "config_local_directory",
    "data_directory", "data_local_directory", "datetime", "datetime_utc", "encode_uri_component",
    "env", "env_var", "env_var_or_default", "error", "executable_directory", "extension",
    "file_name", "file_stem", "home_directory", "invocation_directory", "invocation_directory_native",
    "is_dependency", "join", "join_list", "just_executable", "just_pid", "just_version",
    "justfile", "justfile_directory", "kebabcase", "len", "lowercamelcase", "lowercase",
    "module_directory", "module_file", "module_path", "num_cpus", "num_jobs", "os",
    "os_family", "parent_directory", "path_exists", "prepend", "quote", "read", "recipe_name",
    "replace", "replace_regex", "require", "runtime_directory", "semver_matches",
    "sha256", "sha256_file", "shell", "shoutykebabcase", "shoutysnakecase", "show",
    "snakecase", "source_directory", "source_file", "split", "style", "titlecase",
    "trim", "trim_end", "trim_end_match", "trim_end_matches", "trim_start", "trim_start_match",
    "trim_start_matches", "uppercamelcase", "uppercase", "uuid", "which", "without_extension",
  ][:]
}

///|
pub fn registry() -> ArrayView[BuiltinSpec] {
  names().map(fn(name) {
    let purity = match name {
      "blake3_file"
      | "choose"
      | "datetime"
      | "datetime_utc"
      | "env"
      | "env_var"
      | "env_var_or_default"
      | "path_exists"
      | "read"
      | "sha256_file"
      | "shell"
      | "uuid"
      | "which"
      | "arch"
      | "cache_directory"
      | "config_directory"
      | "config_local_directory"
      | "data_directory"
      | "data_local_directory"
      | "executable_directory"
      | "home_directory"
      | "invocation_directory"
      | "invocation_directory_native"
      | "is_dependency"
      | "just_executable"
      | "just_pid"
      | "just_version"
      | "justfile"
      | "justfile_directory"
      | "module_directory"
      | "module_file"
      | "module_path"
      | "num_cpus"
      | "num_jobs"
      | "os"
      | "os_family"
      | "recipe_name"
      | "require"
      | "runtime_directory"
      | "source_directory"
      | "source_file" => Effect
      _ => Pure
    }
    { name, purity }
  })
}

///|
pub fn is_effectful(name : String) -> Bool {
  registry()
  .iter()
  .any(fn(spec) { spec.name() == name && spec.purity() is Effect })
}

///|
fn canonical_name(name : String) -> String {
  match name {
    "path_join" => "join"
    "stem" => "file_stem"
    "regex_matches" => "replace_regex"
    _ => name
  }
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
fn capitalize(value : String) -> String {
  let builder = StringBuilder()
  for index, character in value {
    if index == 0 {
      builder.write_string(upper_ascii(character.to_string()))
    } else {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
fn case_words(value : String) -> Array[String] {
  let words : Array[String] = []
  let mut current = StringBuilder()
  for character in value {
    if character == '_' || character == '-' || character == ' ' {
      if !current.to_string().is_empty() {
        words.push(current.to_string())
        current = StringBuilder()
      }
    } else {
      current.write_char(character)
    }
  }
  if !current.to_string().is_empty() {
    words.push(current.to_string())
  }
  words
}

///|
fn separated_case(value : String, separator : Char, upper : Bool) -> String {
  let words = case_words(value)
  let result : Array[String] = []
  for word in words {
    result.push(if upper { upper_ascii(word) } else { lower_ascii(word) })
  }
  result.join(separator.to_string())
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
      code == 126 {
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

///|
priv struct SemVersion {
  major : Int
  minor : Int
  patch : Int
  prerelease : Array[String]
}

///|
fn parse_semver_int(value : String) -> Int? {
  if value.is_empty() {
    return None
  }
  let mut result = 0
  for character in value {
    if !character.is_ascii_digit() {
      return None
    }
    result = result * 10 + character.to_int() - 48
  }
  if value.length() > 1 && value[0] == '0' {
    return None
  }
  Some(result)
}

///|
fn split_owned(value : String, separator : String) -> Array[String] {
  let result : Array[String] = []
  for part in value.split(separator) {
    result.push("\{part}")
  }
  result
}

///|
fn parse_semver(value : String, partial : Bool) -> SemVersion? {
  let core_and_pre = split_owned(value.trim().to_owned(), "-")
  let core = core_and_pre[0]
  let prerelease : Array[String] = []
  if core_and_pre.length() > 2 {
    return None
  }
  if core_and_pre.length() == 2 {
    for identifier in split_owned(core_and_pre[1], ".") {
      if identifier.is_empty() ||
        (
          identifier.length() > 1 &&
          identifier[0] == '0' &&
          parse_semver_int(identifier) is Some(_)
        ) {
        return None
      }
      prerelease.push("\{identifier}")
    }
  }
  let parts = split_owned(core, ".")
  if parts.length() > 3 || (!partial && parts.length() != 3) {
    return None
  }
  let numbers : Array[Int] = []
  for part in parts {
    match parse_semver_int(part) {
      Some(number) => numbers.push(number)
      None => return None
    }
  }
  while numbers.length() < 3 {
    numbers.push(0)
  }
  Some({ major: numbers[0], minor: numbers[1], patch: numbers[2], prerelease })
}

///|
fn compare_semver(left : SemVersion, right : SemVersion) -> Int {
  if left.major != right.major {
    return if left.major < right.major { -1 } else { 1 }
  }
  if left.minor != right.minor {
    return if left.minor < right.minor { -1 } else { 1 }
  }
  if left.patch != right.patch {
    return if left.patch < right.patch { -1 } else { 1 }
  }
  if left.prerelease.is_empty() && right.prerelease.is_empty() {
    return 0
  }
  if left.prerelease.is_empty() {
    return 1
  }
  if right.prerelease.is_empty() {
    return -1
  }
  let length = Int::min(left.prerelease.length(), right.prerelease.length())
  for index in 0..<length {
    let left_id = left.prerelease[index]
    let right_id = right.prerelease[index]
    if left_id == right_id {
      continue
    }
    let left_number = parse_semver_int(left_id)
    let right_number = parse_semver_int(right_id)
    match left_number {
      Some(left_value) =>
        match right_number {
          Some(right_value) =>
            return if left_value < right_value { -1 } else { 1 }
          None => return -1
        }
      None =>
        match right_number {
          Some(_) => return 1
          None => return if left_id < right_id { -1 } else { 1 }
        }
    }
  }
  if left.prerelease.length() == right.prerelease.length() {
    0
  } else if left.prerelease.length() < right.prerelease.length() {
    -1
  } else {
    1
  }
}

///|
fn compare_operator(
  actual : SemVersion,
  operator : String,
  expected : SemVersion,
) -> Bool {
  let comparison = compare_semver(actual, expected)
  match operator {
    ">" => comparison > 0
    ">=" => comparison >= 0
    "<" => comparison < 0
    "<=" => comparison <= 0
    _ => comparison == 0
  }
}

///|
fn wildcard_clause(
  actual : SemVersion,
  raw : String,
) -> Bool raise BuiltinError {
  let parts = split_owned(raw.trim().to_owned(), ".")
  if parts.length() == 0 || parts.length() > 3 {
    raise InvalidRequirement(value=raw)
  }
  let numbers : Array[Int] = []
  let mut wildcard = false
  for part in parts {
    if part == "*" || part == "x" || part == "X" {
      wildcard = true
      break
    }
    match parse_semver_int(part) {
      Some(number) => numbers.push(number)
      None => raise InvalidRequirement(value=raw)
    }
  }
  if !wildcard && numbers.length() == 3 {
    let expected = parse_semver(raw, false).unwrap()
    return compare_semver(actual, expected) == 0
  }
  if numbers.length() >= 1 && actual.major != numbers[0] {
    return false
  }
  if numbers.length() >= 2 && actual.minor != numbers[1] {
    return false
  }
  true
}

///|
fn semver_clause(actual : SemVersion, raw : String) -> Bool raise BuiltinError {
  let token = raw.trim()
  if token == "" || token == "*" || token == "x" || token == "X" {
    return true
  }
  if token.has_prefix("^") || token.has_prefix("~") {
    let is_caret = token[0] == '^'
    let body = token.view(start_offset=1).to_owned()
    let lower = match parse_semver(body, true) {
      None => raise InvalidRequirement(value=token.to_owned())
      Some(value) => value
    }
    let upper = if is_caret {
      if lower.major > 0 {
        { major: lower.major + 1, minor: 0, patch: 0, prerelease: [] }
      } else if lower.minor > 0 {
        { major: 0, minor: lower.minor + 1, patch: 0, prerelease: [] }
      } else {
        { major: 0, minor: 0, patch: lower.patch + 1, prerelease: [] }
      }
    } else {
      { major: lower.major, minor: lower.minor + 1, patch: 0, prerelease: [] }
    }
    return compare_semver(actual, lower) >= 0 &&
      compare_semver(actual, upper) < 0
  }
  if token.contains("*") ||
    token.contains("x") ||
    token.contains("X") ||
    (
      !token.contains(">") &&
      !token.contains("<") &&
      !token.contains("=") &&
      split_owned(token.to_owned(), ".").length() < 3
    ) {
    return wildcard_clause(actual, token.to_owned())
  }
  let (operator, body) = if token.has_prefix(">=") {
    (">=", token.view(start_offset=2).to_owned())
  } else if token.has_prefix("<=") {
    ("<=", token.view(start_offset=2).to_owned())
  } else if token.has_prefix(">") {
    (">", token.view(start_offset=1).to_owned())
  } else if token.has_prefix("<") {
    ("<", token.view(start_offset=1).to_owned())
  } else if token.has_prefix("=") {
    ("=", token.view(start_offset=1).to_owned())
  } else {
    ("=", token.to_owned())
  }
  let expected = match parse_semver(body, true) {
    None => raise InvalidRequirement(value=token.to_owned())
    Some(value) => value
  }
  compare_operator(actual, operator, expected)
}

///|
fn semver_matches(
  version : String,
  requirement : String,
) -> Bool raise BuiltinError {
  let actual = match parse_semver(version, false) {
    None => raise InvalidRequirement(value=version)
    Some(value) => value
  }
  for alternative in split_owned(requirement, "||") {
    let mut matches = true
    for token in split_owned(alternative.trim().to_owned(), " ") {
      if !token.trim().is_empty() && !semver_clause(actual, token) {
        matches = false
        break
      }
    }
    if matches {
      return true
    }
  }
  false
}

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
      let (collection, value) = two(name, arguments)
      match collection {
        List(values) => {
          let result = values.copy()
          result.push(value)
          List(result)
        }
        _ => raise Type(name~, expected="list", actual=collection.kind())
      }
    }
    "prepend" => {
      let (value, collection) = two(name, arguments)
      match collection {
        List(values) => {
          let result : Array[Value] = [value]
          for item in values {
            result.push(item)
          }
          List(result)
        }
        _ => raise Type(name~, expected="list", actual=collection.kind())
      }
    }
    "bool" => Bool(one(name, arguments).truthy())
    "error" =>
      raise Failure(message=string_argument(name, one(name, arguments)))
    "capitalize" =>
      String(capitalize(string_argument(name, one(name, arguments))))
    "encode_uri_component" =>
      String(encode_uri_component(string_argument(name, one(name, arguments))))
    "file_stem" =>
      String(
        path_value(name, one(name, arguments))
        .without_extension()
        .file_name()
        .unwrap_or(""),
      )
    "join_list" => {
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
        _ => raise Type(name~, expected="list", actual=collection.kind())
      }
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
      match value {
        String(text) => String(text.length().to_string())
        List(values) => String(values.length().to_string())
        Bool(_) =>
          raise Type(name~, expected="string or list", actual=value.kind())
      }
    }
    "parent_directory" => {
      let path = path_value(name, one(name, arguments))
      String(path.parent().map(fn(value) { value.as_string() }).unwrap_or("."))
    }
    "split" => {
      let (value, separator) = two(name, arguments)
      let value = string_argument(name, value)
      let separator = string_argument(name, separator)
      let result : Array[Value] = []
      for item in value.split(separator) {
        result.push(String("\{item}"))
      }
      List(result)
    }
    "show" => String(one(name, arguments).to_string())
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
      let result = if name == "trim_end_match" || name == "trim_end_matches" {
        if value.has_suffix(match_value) {
          value
          .view(end_offset=value.length() - match_value.length())
          .to_owned()
        } else {
          value
        }
      } else if value.has_prefix(match_value) {
        value.view(start_offset=match_value.length()).to_owned()
      } else {
        value
      }
      String(result)
    }
    "join" => {
      if requested == "path_join" {
        if arguments.length() < 1 {
          raise Arity(name=requested, expected="at least 1", actual=0)
        }
        let mut path = path_value(requested, arguments[0])
        for value in arguments[1:] {
          let child = path_value(requested, value)
          path = path.join(child) catch {
            _ => raise InvalidPath(value=path.as_string())
          }
        }
        return String(path.as_string())
      }
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
    "file_name" =>
      String(path_value(name, one(name, arguments)).file_name().unwrap_or(""))
    "extension" =>
      String(path_value(name, one(name, arguments)).extension().unwrap_or(""))
    "without_extension" =>
      String(
        path_value(name, one(name, arguments)).without_extension().as_string(),
      )
    "replace_regex" => {
      if arguments.length() != 2 && arguments.length() != 3 {
        raise Arity(name~, expected="2 or 3", actual=arguments.length())
      }
      let value = string_argument(name, arguments[0])
      let pattern = string_argument(name, arguments[1])
      if pattern.contains("\\1") ||
        pattern.contains("(?<=") ||
        pattern.contains("(?<!") {
        raise InvalidPattern(value=pattern)
      }
      let regexp = @regexp.compile(pattern[:]) catch {
        _ => raise InvalidPattern(value=pattern)
      }
      let result = regexp.execute(value[:])
      if arguments.length() == 2 {
        Bool(result.matched())
      } else if !result.matched() {
        String(value)
      } else {
        let replacement = string_argument(name, arguments[2])
        String(
          result.before().to_owned() + replacement + result.after().to_owned(),
        )
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
