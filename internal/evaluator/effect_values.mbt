///|
fn value_strings(
  name : String,
  value : Value,
  span : @source.Span,
) -> Array[String] raise EvaluationError {
  match value {
    String(text) => [text]
    List(values) => {
      let result : Array[String] = []
      for value in values {
        match value {
          String(text) => result.push(text)
          other =>
            raise TypeMismatch(
              expected=name + " string list",
              actual=other.kind(),
              span~,
            )
        }
      }
      result
    }
    other =>
      raise TypeMismatch(
        expected=name + " string or string list",
        actual=other.kind(),
        span~,
      )
  }
}

///|
fn[T : @host.HostEnv] env_value(
  host : T,
  name : String,
  keys : Value,
  default : Value?,
  span : @source.Span,
) -> Value raise EvaluationError {
  let keys = value_strings(name, keys, span)
  for key in keys {
    let found = @host.HostEnv::env_get(host, key) catch {
      error => raise Host(error, span~)
    }
    match found {
      Some(value) => return String(value)
      None => ()
    }
  }
  match default {
    Some(value) => value
    None => {
      if keys.is_empty() {
        raise effect_failure(
          "empty environment variable list with no default", span,
        )
      }
      raise effect_failure(
        "environment variable not present: " + keys.join(", "),
        span,
      )
    }
  }
}

///|
fn[T : @host.HostRandom] random_u32(
  host : T,
  span : @source.Span,
) -> UInt64 raise EvaluationError {
  let bytes = @host.HostRandom::random_bytes(host, 4) catch {
    error => raise Host(error, span~)
  }
  if bytes.length() != 4 {
    raise effect_failure("random host returned an invalid byte count", span)
  }
  let mut value = 0UL
  for index, byte in bytes {
    value = value | (byte.to_uint().to_uint64() << (index * 8))
  }
  value
}

///|
fn[T : @host.HostRandom] choose_value(
  host : T,
  arguments : Array[Value],
  span : @source.Span,
) -> Value raise EvaluationError {
  let count_text = expect_string("choose", arguments, 0, span)
  let count = @string.parse_int(count_text[:]) catch {
    _ =>
      raise effect_failure(
        "call to function `choose` failed: failed to parse `" +
        count_text +
        "` as positive integer: invalid digit found in string",
        span,
      )
  }
  if count < 0 {
    raise effect_failure(
      "call to function `choose` failed: choose count must not be negative", span,
    )
  }
  let alphabet_text = expect_string("choose", arguments, 1, span)
  let alphabet = alphabet_text.to_array()
  if alphabet.is_empty() {
    raise effect_failure(
      "call to function `choose` failed: empty alphabet", span,
    )
  }
  let unique : Set[Char] = Set([])
  for character in alphabet {
    if unique.contains(character) {
      raise effect_failure(
        "call to function `choose` failed: alphabet contains repeated character `" +
        character.to_string() +
        "`",
        span,
      )
    }
    unique.add(character)
  }
  let range = 1UL << 32
  let bound = alphabet.length().reinterpret_as_uint().to_uint64()
  let limit = range - range % bound
  let builder = StringBuilder()
  for _ in 0..<count {
    let mut random = random_u32(host, span)
    while random >= limit {
      random = random_u32(host, span)
    }
    builder.write_char(alphabet[(random % bound).to_int()])
  }
  String(builder.to_string())
}

///|
fn hex_digit(character : Char) -> Int? {
  if character >= '0' && character <= '9' {
    Some(character.to_int() - '0'.to_int())
  } else if character >= 'a' && character <= 'f' {
    Some(character.to_int() - 'a'.to_int() + 10)
  } else if character >= 'A' && character <= 'F' {
    Some(character.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn rgb_code(value : String) -> (Int, Int, Int)? {
  let digits = value.to_array()
  if digits.length() == 3 {
    guard hex_digit(digits[0]) is Some(r) else { return None }
    guard hex_digit(digits[1]) is Some(g) else { return None }
    guard hex_digit(digits[2]) is Some(b) else { return None }
    Some((r * 17, g * 17, b * 17))
  } else if digits.length() == 6 {
    guard hex_digit(digits[0]) is Some(r1) else { return None }
    guard hex_digit(digits[1]) is Some(r2) else { return None }
    guard hex_digit(digits[2]) is Some(g1) else { return None }
    guard hex_digit(digits[3]) is Some(g2) else { return None }
    guard hex_digit(digits[4]) is Some(b1) else { return None }
    guard hex_digit(digits[5]) is Some(b2) else { return None }
    Some((r1 * 16 + r2, g1 * 16 + g2, b1 * 16 + b2))
  } else {
    None
  }
}

///|
fn style_code(style : String) -> String? {
  let (background, token) = if style.has_prefix("bg:") {
    (true, style.view(start_offset=3).to_owned())
  } else if style.has_prefix("fg:") {
    (false, style.view(start_offset=3).to_owned())
  } else {
    (false, style)
  }
  let basic = match token {
    "bold" => Some("1")
    "dim" => Some("2")
    "italic" => Some("3")
    "underline" => Some("4")
    "blink" => Some("5")
    "reverse" => Some("7")
    "hidden" => Some("8")
    "strikethrough" => Some("9")
    "black" => Some(if background { "40" } else { "30" })
    "red" => Some(if background { "41" } else { "31" })
    "green" => Some(if background { "42" } else { "32" })
    "yellow" => Some(if background { "43" } else { "33" })
    "blue" => Some(if background { "44" } else { "34" })
    "magenta" => Some(if background { "45" } else { "35" })
    "cyan" => Some(if background { "46" } else { "36" })
    "white" => Some(if background { "47" } else { "37" })
    _ => None
  }
  match basic {
    Some(code) =>
      if (style.has_prefix("fg:") || style.has_prefix("bg:")) &&
        token != "black" &&
        token != "red" &&
        token != "green" &&
        token != "yellow" &&
        token != "blue" &&
        token != "magenta" &&
        token != "cyan" &&
        token != "white" {
        None
      } else {
        Some(code)
      }
    None =>
      if token.has_prefix("#") {
        match rgb_code(token.view(start_offset=1).to_owned()) {
          Some((red, green, blue)) =>
            Some(
              (if background { "48" } else { "38" }) +
              ";2;" +
              red.to_string() +
              ";" +
              green.to_string() +
              ";" +
              blue.to_string(),
            )
          None => None
        }
      } else {
        let fixed = @string.parse_int(token[:]) catch { _ => return None }
        if fixed < 0 || fixed > 255 {
          None
        } else {
          Some(
            (if background { "48" } else { "38" }) + ";5;" + fixed.to_string(),
          )
        }
      }
  }
}

///|
fn[T : @host.HostTerminal] style_value(
  host : T,
  arguments : Array[Value],
  context : EvaluationContext,
  span : @source.Span,
) -> Value raise EvaluationError {
  let styles = value_strings("style", arguments[0], span)
  let text = if arguments.length() == 2 {
    expect_string("style", arguments, 1, span)
  } else {
    ""
  }
  let terminal = @host.HostTerminal::terminal_info(host) catch {
    error => raise Host(error, span~)
  }
  let mode = context.color_mode().unwrap_or("auto")
  let mut active = true
  let mut stream_selected = false
  let properties : Array[String] = []
  let mut foreground : String? = None
  let mut background : String? = None
  fn add_property(properties : Array[String], code : String) -> Unit {
    if !properties.contains(code) {
      properties.push(code)
    }
  }
  for style in styles {
    match style {
      "stdout" => {
        stream_selected = true
        active = active && terminal.stdout_is_terminal()
      }
      "stderr" => {
        stream_selected = true
        active = active && terminal.stderr_is_terminal()
      }
      "command" => {
        add_property(properties, "1")
        match context.command_color() {
          Some(color) => foreground = style_code(color)
          None => ()
        }
      }
      "error" => {
        add_property(properties, "1")
        foreground = Some("31")
      }
      "warning" => {
        add_property(properties, "1")
        foreground = Some("33")
      }
      _ =>
        match style_code(style) {
          Some(code) =>
            if style.has_prefix("bg:") {
              background = Some(code)
            } else if [
                "bold", "dim", "italic", "underline", "blink", "reverse", "hidden",
                "strikethrough",
              ].contains(style) {
              add_property(properties, code)
            } else {
              foreground = Some(code)
            }
          None =>
            raise effect_failure(
              "call to function `style` failed: invalid style: `" + style + "`",
              span,
            )
        }
    }
  }
  if stream_selected {
    active = match mode {
      "always" => true
      "never" => false
      _ => active && terminal.color_supported()
    }
  }
  let codes = properties.copy()
  match background {
    Some(code) => codes.push(code)
    None => ()
  }
  match foreground {
    Some(code) => codes.push(code)
    None => ()
  }
  if !active || codes.is_empty() {
    String(text)
  } else if arguments.length() == 1 {
    String("\u{001b}[" + codes.join(";") + "m")
  } else {
    String("\u{001b}[" + codes.join(";") + "m" + text + "\u{001b}[0m")
  }
}

///|
fn which_extensions(
  executable : String,
  platform : @host.PlatformInfo,
  pathext : String?,
  span : @source.Span,
) -> Array[String] raise EvaluationError {
  let extensions = [""]
  if platform.operating_system() != Windows {
    return extensions
  }
  let path = @path.PathValue::new(executable, platform.path_flavor()) catch {
    _ => raise effect_failure("invalid executable path", span)
  }
  if path.extension() is Some(_) {
    return extensions
  }
  guard pathext is Some(value) else { return extensions }
  for raw_extension in value.split(";") {
    let extension = raw_extension.to_owned()
    if !extension.has_prefix(".") {
      raise effect_failure(
        "`PATHEXT` entry `" + extension + "` does not start with `.`",
        span,
      )
    }
    extensions.push(extension)
  }
  extensions
}

///|
fn which_candidates(
  executable : String,
  context : EvaluationContext,
  path : String,
  platform : @host.PlatformInfo,
  pathext : String?,
  span : @source.Span,
) -> Array[@path.PathValue] raise EvaluationError {
  let cwd = require_context_path("cwd", context.cwd, span)
  let extensions = which_extensions(executable, platform, pathext, span)
  let direct = executable.contains("/") ||
    executable.contains("\\") ||
    (platform.operating_system() == Windows && executable.contains(":"))
  let bases : Array[@path.PathValue] = []
  if direct {
    bases.push(resolve_context_path(context, executable, span))
  } else {
    let separator = if platform.operating_system() == Windows {
      ";"
    } else {
      ":"
    }
    for raw_directory in path.split(separator) {
      let directory = @path.PathValue::new(
        raw_directory.to_owned(),
        cwd.flavor(),
      ) catch {
        _ => continue
      }
      let base = if directory.is_absolute() {
        directory
      } else {
        cwd.join(directory) catch {
          _ => continue
        }
      }
      let child = @path.PathValue::new(executable, cwd.flavor()) catch {
        _ => continue
      }
      bases.push(base.join(child) catch { _ => continue })
    }
  }
  let candidates : Array[@path.PathValue] = []
  for base in bases {
    for extension in extensions {
      let candidate = @path.PathValue::new(
        base.as_string() + extension,
        base.flavor(),
      ) catch {
        _ => continue
      }
      candidates.push(candidate)
    }
  }
  candidates
}

///|
fn windows_candidate_is_executable(
  candidate : @path.PathValue,
  metadata : @host.FileMetadata,
  pathext : String?,
) -> Bool {
  guard metadata.is_file() else { return false }
  guard candidate.extension() is Some(extension) else { return false }
  guard pathext is Some(value) else { return metadata.is_executable() }
  for raw_extension in value.split(";") {
    if raw_extension.length() > 1 &&
      extension.to_lower() == raw_extension[1:].to_owned().to_lower() {
      return true
    }
  }
  false
}

///|
