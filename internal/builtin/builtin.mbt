///|
/// Names of pure builtins supported by the evaluator.
type Value = @value.Value

///|
pub(all) enum BuiltinPurity {
  Pure
  Effect
} derive(Eq, Debug)

///|
pub(all) enum BuiltinCapability {
  Context
  FsRead
  Environment
  Clock
  Random
  Process
  Platform
  Terminal
} derive(Eq, Debug)

///|
pub(all) enum BuiltinTarget {
  Native
  Wasm1
} derive(Eq, Debug)

///|
pub(all) struct BuiltinSpec {
  name : String
  purity : BuiltinPurity
  min_arguments : Int
  max_arguments : Int?
  aliases : Array[String]
  capabilities : Array[BuiltinCapability]
  targets : Array[BuiltinTarget]
  evidence : String
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
pub fn BuiltinSpec::min_arguments(self : BuiltinSpec) -> Int {
  self.min_arguments
}

///|
pub fn BuiltinSpec::max_arguments(self : BuiltinSpec) -> Int? {
  self.max_arguments
}

///|
pub fn BuiltinSpec::aliases(self : BuiltinSpec) -> ArrayView[String] {
  self.aliases[:]
}

///|
pub fn BuiltinSpec::capabilities(
  self : BuiltinSpec,
) -> ArrayView[BuiltinCapability] {
  self.capabilities[:]
}

///|
pub fn BuiltinSpec::targets(self : BuiltinSpec) -> ArrayView[BuiltinTarget] {
  self.targets[:]
}

///|
pub fn BuiltinSpec::evidence(self : BuiltinSpec) -> String {
  self.evidence
}

///|
pub fn BuiltinSpec::accepts_arity(self : BuiltinSpec, actual : Int) -> Bool {
  actual >= self.min_arguments &&
  (match self.max_arguments {
    Some(maximum) => actual <= maximum
    None => true
  })
}

///|
pub fn BuiltinSpec::arity_description(self : BuiltinSpec) -> String {
  match self.max_arguments {
    Some(maximum) =>
      if maximum == self.min_arguments {
        maximum.to_string()
      } else {
        self.min_arguments.to_string() + " or " + maximum.to_string()
      }
    None => self.min_arguments.to_string() + " or more"
  }
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
fn builtin_arity(name : String) -> (Int, Int?) {
  match name {
    "arch"
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
    | "runtime_directory"
    | "source_directory"
    | "source_file"
    | "uuid" => (0, Some(0))
    "env" | "join_list" | "split" | "style" => (1, Some(2))
    "append"
    | "choose"
    | "env_var_or_default"
    | "prepend"
    | "semver_matches"
    | "trim_end_match"
    | "trim_end_matches"
    | "trim_start_match"
    | "trim_start_matches" => (2, Some(2))
    "replace" | "replace_regex" => (3, Some(3))
    "join" => (2, None)
    "shell" => (1, None)
    _ => (1, Some(1))
  }
}

///|
fn builtin_capabilities(name : String) -> Array[BuiltinCapability] {
  match name {
    "arch" | "os" | "os_family" => [Platform]
    "blake3_file" | "canonicalize" | "path_exists" | "read" | "sha256_file" =>
      [Context, FsRead]
    "env" | "env_var" | "env_var_or_default" => [Environment]
    "datetime" => [Context, Clock]
    "datetime_utc" => [Clock]
    "choose" | "uuid" => [Random]
    "shell" => [Context, Process]
    "which" | "require" => [Context, FsRead, Environment, Platform]
    "style" => [Terminal]
    "absolute_path"
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
    | "recipe_name"
    | "runtime_directory"
    | "source_directory"
    | "source_file" => [Context]
    _ => []
  }
}

///|
fn builtin_aliases(name : String) -> Array[String] {
  let aliases : Array[String] = []
  if name.has_suffix("_directory_native") {
    aliases.push(
      name
      .view(end_offset=name.length() - "_directory_native".length())
      .to_owned() +
      "_dir_native",
    )
  } else if name.has_suffix("_directory") {
    aliases.push(
      name.view(end_offset=name.length() - "_directory".length()).to_owned() +
      "_dir",
    )
  }
  aliases
}

///|
pub fn registry() -> ArrayView[BuiltinSpec] {
  names().map(fn(name) {
    let (min_arguments, max_arguments) = builtin_arity(name)
    let capabilities = builtin_capabilities(name)
    let purity = if capabilities.is_empty() { Pure } else { Effect }
    {
      name,
      purity,
      min_arguments,
      max_arguments,
      aliases: builtin_aliases(name),
      capabilities,
      targets: [Native, Wasm1],
      evidence: "tests/upstream/just-1.57.0/builtins.jsonl#" + name,
    }
  })
}

///|
pub fn is_effectful(name : String) -> Bool {
  match find(name) {
    Some(spec) => spec.purity() is Effect
    None => false
  }
}

///|
pub fn canonical_name(name : String) -> String {
  let compatibility = match name {
    "path_join" => "join"
    "stem" => "file_stem"
    "regex_matches" => "replace_regex"
    _ => name
  }
  if compatibility.has_suffix("_dir_native") {
    compatibility
    .view(end_offset=compatibility.length() - "_dir_native".length())
    .to_owned() +
    "_directory_native"
  } else if compatibility.has_suffix("_dir") {
    compatibility
    .view(end_offset=compatibility.length() - "_dir".length())
    .to_owned() +
    "_directory"
  } else {
    compatibility
  }
}

///|
pub fn find(name : String) -> BuiltinSpec? {
  let canonical = canonical_name(name)
  registry().iter().find_first(fn(spec) { spec.name() == canonical })
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
    None => raise Type(name~, expected="string", actual=value)
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
fn replacement_name_character(character : Char) -> Bool {
  character.is_ascii_lowercase() ||
  character.is_ascii_uppercase() ||
  character.is_ascii_digit() ||
  character == '_'
}

///|
fn replacement_capture_index(regexp : @regexp.Regexp, name : String) -> Int? {
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
          match result.get(capture) {
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
        match result.get(capture) {
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
  value : String,
  replacement : String,
) -> String {
  let builder = StringBuilder()
  let mut remaining = value
  for ;; {
    let result = regexp.execute(remaining[:])
    if !result.matched() {
      builder.write_string(remaining)
      break
    }
    builder.write_stringview(result.before())
    write_replacement(regexp, result, replacement, builder)
    let matched = result.get(0).unwrap()
    let after = result.after().to_owned()
    if matched.length() == 0 {
      if after.length() == 0 {
        break
      }
      let after_characters = after.to_array()
      builder.write_char(after_characters[0])
      remaining = String::from_array(after_characters[1:])
    } else {
      remaining = after
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
      builder.write_string(lower_ascii(character.to_string()))
    }
  }
  builder.to_string()
}

///|
fn case_words(value : String) -> Array[String] {
  let words : Array[String] = []
  let mut current = StringBuilder()
  let mut previous_lower = false
  for character in value {
    let separator = character == '_' || character == '-' || character == ' '
    let camel_boundary = character.is_ascii_uppercase() && previous_lower
    if separator || camel_boundary {
      if !current.to_string().is_empty() {
        words.push(current.to_string())
        current = StringBuilder()
      }
    }
    if !separator {
      current.write_char(character)
    }
    previous_lower = character.is_ascii_lowercase() ||
      character.is_ascii_digit()
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
fn whitespace_words(value : String) -> Array[String] {
  let words : Array[String] = []
  let mut current = StringBuilder()
  for character in value {
    if character.is_ascii_whitespace() {
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
fn valid_semver_identifier(value : String) -> Bool {
  if value == "" {
    return false
  }
  for character in value {
    if !character.is_ascii_lowercase() &&
      !character.is_ascii_uppercase() &&
      !character.is_ascii_digit() &&
      character != '-' {
      return false
    }
  }
  true
}

///|
fn parse_semver(value : String, partial : Bool) -> SemVersion? {
  let trimmed = value.trim().to_owned()
  let (without_build, build) = match trimmed.find("+") {
    Some(index) =>
      (
        trimmed.view(end_offset=index).to_owned(),
        Some(trimmed.view(start_offset=index + 1).to_owned()),
      )
    None => (trimmed, None)
  }
  match build {
    Some(value) => {
      if value.contains("+") {
        return None
      }
      for identifier in split_owned(value, ".") {
        if !valid_semver_identifier(identifier) {
          return None
        }
      }
    }
    None => ()
  }
  let (core, prerelease_text) = match without_build.find("-") {
    Some(index) =>
      (
        without_build.view(end_offset=index).to_owned(),
        Some(without_build.view(start_offset=index + 1).to_owned()),
      )
    None => (without_build, None)
  }
  let prerelease : Array[String] = []
  match prerelease_text {
    Some(text) =>
      for identifier in split_owned(text, ".") {
        if !valid_semver_identifier(identifier) ||
          (
            identifier.length() > 1 &&
            identifier[0] == '0' &&
            parse_semver_int(identifier) is Some(_)
          ) {
          return None
        }
        prerelease.push("\{identifier}")
      }
    None => ()
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
fn semver_component_count(value : String) -> Int {
  let mut core = value
  match core.find("+") {
    Some(index) => core = core.view(end_offset=index).to_owned()
    None => ()
  }
  match core.find("-") {
    Some(index) => core = core.view(end_offset=index).to_owned()
    None => ()
  }
  split_owned(core, ".").length()
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
fn wildcard_clause(
  actual : SemVersion,
  raw : String,
  operator : String,
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
      continue
    }
    if wildcard {
      raise InvalidRequirement(value=raw)
    }
    match parse_semver_int(part) {
      Some(number) => numbers.push(number)
      None => raise InvalidRequirement(value=raw)
    }
  }
  if !wildcard {
    raise InvalidRequirement(value=raw)
  }
  if numbers.is_empty() {
    raise InvalidRequirement(value=raw)
  }
  let components = numbers.length()
  while numbers.length() < 3 {
    numbers.push(0)
  }
  let expected : SemVersion = {
    major: numbers[0],
    minor: numbers[1],
    patch: numbers[2],
    prerelease: [],
  }
  match operator {
    "=" => exact_partial(actual, expected, components)
    ">" => greater_partial(actual, expected, components)
    ">=" =>
      exact_partial(actual, expected, components) ||
      greater_partial(actual, expected, components)
    "<" => less_partial(actual, expected, components)
    "<=" =>
      exact_partial(actual, expected, components) ||
      less_partial(actual, expected, components)
    "^" => compatible_partial(actual, expected, components, true)
    "~" => compatible_partial(actual, expected, components, false)
    _ => false
  }
}

///|
fn normalize_semver_token(raw : String) -> String? {
  let token = raw.trim().to_owned()
  let (operator, body) = if token.has_prefix(">=") || token.has_prefix("<=") {
    (
      token.view(end_offset=2).to_owned(),
      token.view(start_offset=2).trim_start().to_owned(),
    )
  } else if token.has_prefix(">") ||
    token.has_prefix("<") ||
    token.has_prefix("=") ||
    token.has_prefix("^") ||
    token.has_prefix("~") {
    (
      token.view(end_offset=1).to_owned(),
      token.view(start_offset=1).trim_start().to_owned(),
    )
  } else {
    ("", token)
  }
  if body == "" || body.contains(" ") || body.contains("\t") {
    None
  } else {
    Some(operator + body)
  }
}

///|
fn exact_partial(
  actual : SemVersion,
  expected : SemVersion,
  components : Int,
) -> Bool {
  actual.major == expected.major &&
  (components < 2 || actual.minor == expected.minor) &&
  (components < 3 || actual.patch == expected.patch) &&
  actual.prerelease == expected.prerelease
}

///|
fn greater_partial(
  actual : SemVersion,
  expected : SemVersion,
  components : Int,
) -> Bool {
  if actual.major != expected.major {
    return actual.major > expected.major
  }
  if components < 2 {
    return false
  }
  if actual.minor != expected.minor {
    return actual.minor > expected.minor
  }
  if components < 3 {
    return false
  }
  compare_semver(actual, expected) > 0
}

///|
fn less_partial(
  actual : SemVersion,
  expected : SemVersion,
  components : Int,
) -> Bool {
  if actual.major != expected.major {
    return actual.major < expected.major
  }
  if components < 2 {
    return false
  }
  if actual.minor != expected.minor {
    return actual.minor < expected.minor
  }
  if components < 3 {
    return false
  }
  compare_semver(actual, expected) < 0
}

///|
fn compatible_partial(
  actual : SemVersion,
  expected : SemVersion,
  components : Int,
  caret : Bool,
) -> Bool {
  if actual.major != expected.major {
    return false
  }
  if !caret {
    if components >= 2 && actual.minor != expected.minor {
      return false
    }
    if components >= 3 && actual.patch != expected.patch {
      return actual.patch > expected.patch
    }
    return compare_semver(actual, expected) >= 0
  }
  if components < 2 {
    return true
  }
  if components < 3 {
    return if expected.major > 0 {
      actual.minor >= expected.minor
    } else {
      actual.minor == expected.minor
    }
  }
  if expected.major > 0 {
    if actual.minor != expected.minor {
      return actual.minor > expected.minor
    }
    if actual.patch != expected.patch {
      return actual.patch > expected.patch
    }
  } else if expected.minor > 0 {
    if actual.minor != expected.minor {
      return false
    }
    if actual.patch != expected.patch {
      return actual.patch > expected.patch
    }
  } else if actual.minor != expected.minor || actual.patch != expected.patch {
    return false
  }
  compare_semver(actual, expected) >= 0
}

///|
fn semver_clause(actual : SemVersion, raw : String) -> Bool raise BuiltinError {
  let raw_token = raw.trim().to_owned()
  if raw_token == "*" || raw_token == "x" || raw_token == "X" {
    return true
  }
  let token = match normalize_semver_token(raw) {
    Some(value) => value
    None => raise InvalidRequirement(value=raw)
  }
  let explicit_comparator = token.has_prefix("^") ||
    token.has_prefix("~") ||
    token.has_prefix(">") ||
    token.has_prefix("<") ||
    token.has_prefix("=")
  let wildcard = token.contains("*") ||
    token.contains("x") ||
    token.contains("X")
  if (!wildcard && token.has_prefix("^")) ||
    (!wildcard && token.has_prefix("~")) ||
    (!explicit_comparator && !wildcard) {
    let is_caret = !token.has_prefix("~")
    let body = if token.has_prefix("^") || token.has_prefix("~") {
      token.view(start_offset=1).to_owned()
    } else {
      token
    }
    let lower = match parse_semver(body, true) {
      None => raise InvalidRequirement(value=token)
      Some(value) => value
    }
    let components = semver_component_count(body)
    return compatible_partial(actual, lower, components, is_caret)
  }
  if wildcard {
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
    } else if token.has_prefix("^") {
      ("^", token.view(start_offset=1).to_owned())
    } else if token.has_prefix("~") {
      ("~", token.view(start_offset=1).to_owned())
    } else {
      ("=", token)
    }
    return wildcard_clause(actual, body, operator)
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
    ("=", token)
  }
  let expected = match parse_semver(body, true) {
    None => raise InvalidRequirement(value=token)
    Some(value) => value
  }
  let components = semver_component_count(body)
  match operator {
    "=" => exact_partial(actual, expected, components)
    ">" => greater_partial(actual, expected, components)
    ">=" =>
      exact_partial(actual, expected, components) ||
      greater_partial(actual, expected, components)
    "<" => less_partial(actual, expected, components)
    "<=" =>
      exact_partial(actual, expected, components) ||
      less_partial(actual, expected, components)
    _ => false
  }
}

///|
fn semver_clause_prerelease(actual : SemVersion, raw : String) -> Bool {
  let raw_token = raw.trim().to_owned()
  if raw_token == "" || raw_token == "*" || raw_token == "x" || raw_token == "X" {
    return false
  }
  let token = match normalize_semver_token(raw) {
    Some(value) => value
    None => return false
  }
  let mut start = 0
  while start < token.length() &&
        (
          token[start] == '>' ||
          token[start] == '<' ||
          token[start] == '=' ||
          token[start] == '^' ||
          token[start] == '~'
        ) {
    start += 1
  }
  let body = token.view(start_offset=start).to_owned()
  match parse_semver(body, true) {
    Some(expected) =>
      !expected.prerelease.is_empty() &&
      expected.major == actual.major &&
      expected.minor == actual.minor &&
      expected.patch == actual.patch
    None => false
  }
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
  if requirement.trim() == "" || requirement.contains("||") {
    raise InvalidRequirement(value=requirement)
  }
  let mut prerelease_allowed = false
  for token in split_owned(requirement, ",") {
    let token = token.trim().to_owned()
    if token == "" {
      raise InvalidRequirement(value=requirement)
    }
    if !semver_clause(actual, token) {
      return false
    }
    if semver_clause_prerelease(actual, token) {
      prerelease_allowed = true
    }
  }
  actual.prerelease.is_empty() || prerelease_allowed
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
