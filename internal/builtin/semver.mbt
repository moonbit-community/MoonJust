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
  Some({ major: numbers[0], minor: numbers[1], patch: numbers[2], prerelease, })
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
