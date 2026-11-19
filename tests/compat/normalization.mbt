///|
fn normalize(bytes : Bytes, root : String) -> Bytes {
  if root.is_empty() {
    return bytes
  }
  let private_root = @utf8.encode("/private" + root)[:]
  let normalized = @testkit.replace_bytes(
    bytes,
    private_root,
    b"<CASE_ROOT>"[:],
  )
  let escaped_root = @utf8.encode(root.replace_all(old="\\", new="\\\\"))[:]
  let normalized = @testkit.replace_bytes(
    normalized,
    escaped_root,
    b"<CASE_ROOT>"[:],
  )
  let normalized = @testkit.replace_bytes(
    normalized,
    @utf8.encode(root)[:],
    b"<CASE_ROOT>"[:],
  )
  @testkit.replace_bytes(normalized, b"/private/tmp/"[:], b"/tmp/"[:])
}

///|
fn normalize_snapshot(
  result : CaseResult,
  program : String,
  rules : ArrayView[String],
) -> CaseResult {
  {
    ..result,
    stdout: normalize_output(result.stdout, "", program, rules, stdout=true),
    stderr: normalize_output(result.stderr, "", program, rules),
    merged: result.merged.map(fn(value) {
      normalize_output(value, "", program, rules)
    }),
    steps: result.steps.map(fn(step) {
      {
        status: step.status,
        stdout: normalize_output(step.stdout, "", program, rules, stdout=true),
        stderr: normalize_output(step.stderr, "", program, rules),
      }
    }),
  }
}

///|
/// Apply only fixture-declared, structural normalizations. These rules are
/// intentionally finite and deterministic; all fields not named by a rule
/// remain byte-for-byte comparable.
fn normalize_output(
  bytes : Bytes,
  root : String,
  program : String,
  rules : ArrayView[String],
  stdout~ : Bool = false,
) -> Bytes {
  let base = normalize(bytes, root)
  let text = @utf8.decode(base) catch { _ => return base }
  let mut result = text
  for rule in rules {
    result = match rule {
      "datetime" => normalize_datetime(result)
      "duration" => normalize_duration(result)
      "timestamp" if !stdout => normalize_timestamp(result)
      "choose" => normalize_choice(result)
      "uuid" if stdout => normalize_uuid(result)
      "parallel-order" if stdout => normalize_parallel_order(result)
      "program-path" => normalize_program_path(result)
      "temp-path" => normalize_temp_path(result)
      "canonical-path" => normalize_canonical_path(result)
      "module-path" =>
        result.replace_all(old="<CASE_ROOT>/foo.just", new="foo.just")
      _ => result
    }
  }
  // The program path is an execution detail only when explicitly declared by
  // the fixture; this keeps ordinary diagnostics exact.
  if rules.contains("program-path") && !program.is_empty() {
    result = result.replace_all(old=program, new="<JUST>")
  }
  @utf8.encode(result)
}

///|
fn decimal_digit(character : Char) -> Bool {
  character >= '0' && character <= '9'
}

///|
fn decimal_range(text : String, start : Int32, length : Int32) -> Bool {
  let view = text[start:start + length]
  for character in view {
    if !decimal_digit(character) {
      return false
    }
  }
  true
}

///|
fn normalize_datetime(text : String) -> String {
  guard text.length() >= 10 else { return text }
  guard text[4] == '-' && text[7] == '-' else { return text }
  guard decimal_range(text, 0, 4) &&
    decimal_range(text, 5, 2) &&
    decimal_range(text, 8, 2) else {
    return text
  }
  "<DATE>" + text[10:].to_owned()
}

///|
fn normalize_duration(text : String) -> String {
  guard text.find(" completed in ") is Some(start) else { return text }
  let after = start + " completed in ".length()
  guard text[after:].find("s") is Some(end) else { return text }
  let end = after + end
  let value = text[after:end]
  guard !value.is_empty() && value.all(fn(c) { decimal_digit(c) || c == '.' }) else {
    return text
  }
  text[:after].to_owned() + "<DURATION>" + text[end:].to_owned()
}

///|
fn normalize_timestamp(text : String) -> String {
  guard text.has_prefix("[") &&
    text.length() > 11 &&
    text[3] == ':' &&
    text[6] == ':' &&
    text[9] == ']' &&
    text[10] == ' ' &&
    decimal_range(text, 1, 2) &&
    decimal_range(text, 4, 2) &&
    decimal_range(text, 7, 2) else {
    return text
  }
  // The three declared fixtures have one timestamped command each.
  // A multi-command trace must preserve the clock reading of every command.
  guard !text.strip_suffix("\n").unwrap_or(text[:]).contains("\n") &&
    text[1:3] <= "23" &&
    text[4:6] <= "59" &&
    text[7:9] <= "59" else {
    return text
  }
  "[00:00:00]" + text[10:].to_owned()
}

///|
fn normalize_choice(text : String) -> String {
  let suffix = if text.has_suffix("\n") { "\n" } else { "" }
  let value = if suffix.is_empty() {
    text
  } else {
    text[:text.length() - 1].to_owned()
  }
  if value.length() != 10 ||
    value.contains("\n") ||
    !value.all(fn(c) {
      c == 'x' || c == 'X' || c == 'y' || c == 'Y' || c == 'z' || c == 'Z'
    }) {
    text
  } else {
    "<CHOICE>" + suffix
  }
}

///|
fn normalize_uuid(text : String) -> String {
  let suffix = if text.has_suffix("\n") { "\n" } else { "" }
  let value = if suffix.is_empty() {
    text
  } else {
    text[:text.length() - 1].to_owned()
  }
  guard value.length() == 36 else { return text }
  for i in 0..<36 {
    let c = value[i]
    let valid = match i {
      8 | 13 | 18 | 23 => c == '-'
      14 => c == '4'
      19 => c == '8' || c == '9' || c == 'a' || c == 'b'
      _ => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')
    }
    if !valid {
      return text
    }
  }
  // A valid representative keeps normalization idempotent for recordings.
  "00000000-0000-4000-8000-000000000000" + suffix
}

///|
fn normalize_parallel_order(text : String) -> String {
  // These are the two alternatives allowed by each tests/parallel.rs fixture.
  match text {
    "b\nb\na\na\n" => "a\na\nb\nb\n"
    "x\nc\nb\na\n" => "x\nb\nc\na\n"
    _ => text
  }
}

///|
fn normalize_program_path(text : String) -> String {
  guard text.has_prefix("'") && text.find("'") is Some(first) else {
    return text
  }
  guard text[first + 1:].find("'") is Some(offset) else { return text }
  let second = first + 1 + offset
  "'<JUST>" + text[second:].to_owned()
}

///|
fn normalize_temp_path(text : String) -> String {
  let markers = [
    "C:\\Users\\RUNNER~1\\AppData\\Local\\Temp\\moonjust-compat-official.", "C:\\Users\\RUNNER~1\\AppData\\Local\\Temp\\moonjust-compat-candidate.",
    "C:\\Users\\runneradmin\\AppData\\Local\\Temp\\moonjust-compat-official.", "C:\\Users\\runneradmin\\AppData\\Local\\Temp\\moonjust-compat-candidate.",
    "C:\\\\Users\\\\RUNNER~1\\\\AppData\\\\Local\\\\Temp\\\\moonjust-compat-official.",
    "C:\\\\Users\\\\RUNNER~1\\\\AppData\\\\Local\\\\Temp\\\\moonjust-compat-candidate.",
    "C:\\\\Users\\\\runneradmin\\\\AppData\\\\Local\\\\Temp\\\\moonjust-compat-official.",
    "C:\\\\Users\\\\runneradmin\\\\AppData\\\\Local\\\\Temp\\\\moonjust-compat-candidate.",
    "/c/Users/RUNNER~1/AppData/Local/Temp/moonjust-compat-official.", "/c/Users/RUNNER~1/AppData/Local/Temp/moonjust-compat-candidate.",
    "/c/Users/runneradmin/AppData/Local/Temp/moonjust-compat-official.", "/c/Users/runneradmin/AppData/Local/Temp/moonjust-compat-candidate.",
    "C:/Users/RUNNER~1/AppData/Local/Temp/moonjust-compat-official.", "C:/Users/RUNNER~1/AppData/Local/Temp/moonjust-compat-candidate.",
    "C:/Users/runneradmin/AppData/Local/Temp/moonjust-compat-official.", "C:/Users/runneradmin/AppData/Local/Temp/moonjust-compat-candidate.",
  ]
  let mut text = text
  for marker in markers {
    text = replace_windows_temp_root(text, marker)
  }
  let suffix = if text.has_suffix("\n") { "\n" } else { "" }
  if text.is_empty() || (text.contains("\n") && !text.has_suffix("\n")) {
    text
  } else {
    let value = if suffix.is_empty() {
      text
    } else {
      text[:text.length() - 1].to_owned()
    }
    let parts = value.replace_all(old="\\", new="/").split("/").collect()
    guard parts.length() >= 2 &&
      parts.last() is Some(file) &&
      !file.is_empty() &&
      file.has_suffix(".txt") else {
      return text
    }
    "<TEMP_PATH>/" + file.to_owned() + suffix
  }
}

///|
fn normalize_canonical_path(text : String) -> String {
  text
  .replace_all(old="\\\\?\\<CASE_ROOT>", new="<CASE_ROOT>")
  .replace_all(old="\\?\\<CASE_ROOT>", new="<CASE_ROOT>")
  .replace_all(old="\\", new="/")
}

///|
/// Replace only the generated compatibility root component in Windows paths.
/// The token is intentionally finite and marker-based; no arbitrary wildcard
/// or regular-expression matching is used.
fn replace_windows_temp_root(text : String, marker : String) -> String {
  let output = StringBuilder()
  let mut cursor = 0
  while cursor < text.length() {
    let remaining = text[cursor:]
    guard remaining.find(marker) is Some(offset) else {
      output.write_string(remaining.to_owned())
      break
    }
    let start = cursor + offset
    output.write_string(text[cursor:start].to_owned())
    let token_start = start + marker.length()
    let mut token_end = token_start
    for character in text[token_start:] {
      if character == '\\' ||
        character == '/' ||
        character == '"' ||
        character == '\'' ||
        character == ' ' ||
        character == '\n' ||
        character == '\r' ||
        character == ']' {
        break
      }
      token_end += 1
    }
    output.write_string("<CASE_ROOT>")
    cursor = token_end
  }
  output.to_string()
}
