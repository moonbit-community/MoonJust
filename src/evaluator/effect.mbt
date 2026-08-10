///|
fn expect_string(
  name : String,
  arguments : Array[Value],
  index : Int,
  span : @source.Span,
) -> String raise EvaluationError {
  if index >= arguments.length() {
    raise TypeMismatch(expected=name + " argument", actual="missing", span~)
  }
  match arguments[index] {
    String(value) => value
    value => raise TypeMismatch(expected="string", actual=value.kind(), span~)
  }
}

///|
fn bytes_text(
  bytes : Bytes,
  span : @source.Span,
) -> String raise EvaluationError {
  @utf8.decode(bytes) catch {
    _ => raise InvalidUtf8(span~)
  }
}

///|
fn hex_byte(byte : Byte, builder : StringBuilder) -> Unit {
  let digits = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  builder.write_char(digits[(byte.to_int() >> 4) & 15])
  builder.write_char(digits[byte.to_int() & 15])
}

///|
fn uuid_text(bytes : Bytes) -> String {
  let builder = StringBuilder()
  for index, byte in bytes {
    if index == 4 || index == 6 || index == 8 || index == 10 {
      builder.write_char('-')
    }
    let value = if index == 6 {
      ((byte.to_int() & 15) | 64).to_byte()
    } else if index == 8 {
      ((byte.to_int() & 63) | 128).to_byte()
    } else {
      byte
    }
    hex_byte(value, builder)
  }
  builder.to_string()
}

///|
fn validate_effect_arity(
  requested : String,
  arguments : Array[Value],
  span : @source.Span,
) -> String raise EvaluationError {
  let name = @builtin.canonical_name(requested)
  match @builtin.find(name) {
    Some(spec) =>
      if !spec.accepts_arity(arguments.length()) {
        raise Builtin(
          Arity(
            name~,
            expected=spec.arity_description(),
            actual=arguments.length(),
          ),
          span~,
        )
      }
    None => ()
  }
  name
}

///|
/// Shell selected for effectful `shell()` calls and backticks.
pub struct EffectShell {
  program : String
  arguments : Array[String]
} derive(Eq, Debug)

///|
pub fn EffectShell::new(
  program : String,
  arguments : Array[String],
) -> EffectShell {
  { program, arguments: arguments.copy() }
}

///|
pub fn EffectShell::program(self : EffectShell) -> String {
  self.program
}

///|
pub fn EffectShell::arguments(self : EffectShell) -> ArrayView[String] {
  self.arguments[:]
}

///|
fn effect_shell_kind(program : String) -> String {
  let normalized = program.replace(old="\\", new="/")
  normalized.split("/").last().unwrap_or(normalized[:]).to_owned()
}

///|
fn strip_one_line_ending(text : String) -> String {
  if text.has_suffix("\r\n") {
    text[:text.length() - 2].to_owned()
  } else if text.has_suffix("\n") {
    text[:text.length() - 1].to_owned()
  } else {
    text
  }
}

///|
pub fn[T : @host.HostProcess] call_shell_effect(
  host : T,
  arguments : Array[Value],
  context : EvaluationContext,
  shell : EffectShell,
  span : @source.Span,
  quiet? : Bool = false,
) -> Value raise EvaluationError {
  let name = validate_effect_arity("shell", arguments, span)
  let command = expect_string(name, arguments, 0, span)
  let shell_arguments = shell.arguments().to_owned()
  shell_arguments.push(command)
  if arguments.length() > 1 {
    match effect_shell_kind(shell.program()) {
      "cmd"
      | "cmd.exe"
      | "powershell"
      | "powershell.exe"
      | "pwsh"
      | "pwsh.exe" => ()
      _ => shell_arguments.push(command)
    }
    for argument in arguments[1:] {
      shell_arguments.push(expect_string(name, [argument], 0, span))
    }
  }
  let spec = @host.CommandSpec::new(shell.program(), shell_arguments) catch {
    error => raise Host(error, span~)
  }
  let cwd = require_context_path("cwd", context.cwd, span)
  spec.set_cwd(cwd)
  spec.set_inherit_stdin(true)
  spec.set_stdout(Capture)
  spec.set_stderr(if quiet { Discard } else { Inherit })
  let output = @host.HostProcess::run_process(host, spec) catch {
    error => raise Host(error, span~)
  }
  match output.termination() {
    Exited(0) => ()
    Exited(code) => raise ProcessFailure(code~, span~)
    Signaled(signal) => raise ProcessSignaled(signal~, span~)
  }
  let text = bytes_text(output.stdout().to_owned(), span)
  String(strip_one_line_ending(text))
}

///|
/// Async counterpart used by native and wasm execution runtimes. It preserves
/// the exact argv, cwd, stdio, trimming, and failure contract of the sync path.
pub async fn[T : @host.HostAsyncProcess] call_shell_effect_async(
  host : T,
  arguments : Array[Value],
  context : EvaluationContext,
  shell : EffectShell,
  span : @source.Span,
  quiet? : Bool = false,
) -> Value raise EvaluationError {
  let name = validate_effect_arity("shell", arguments, span)
  let command = expect_string(name, arguments, 0, span)
  let shell_arguments = shell.arguments().to_owned()
  shell_arguments.push(command)
  if arguments.length() > 1 {
    match effect_shell_kind(shell.program()) {
      "cmd"
      | "cmd.exe"
      | "powershell"
      | "powershell.exe"
      | "pwsh"
      | "pwsh.exe" => ()
      _ => shell_arguments.push(command)
    }
    for argument in arguments[1:] {
      shell_arguments.push(expect_string(name, [argument], 0, span))
    }
  }
  let spec = @host.CommandSpec::new(shell.program(), shell_arguments) catch {
    error => raise Host(error, span~)
  }
  spec.set_cwd(require_context_path("cwd", context.cwd, span))
  spec.set_inherit_stdin(true)
  spec.set_stdout(Capture)
  spec.set_stderr(if quiet { Discard } else { Inherit })
  let output = @host.HostAsyncProcess::run_process_async(host, spec) catch {
    error => raise Host(error, span~)
  }
  match output.termination() {
    Exited(0) => ()
    Exited(code) => raise ProcessFailure(code~, span~)
    Signaled(signal) => raise ProcessSignaled(signal~, span~)
  }
  String(strip_one_line_ending(bytes_text(output.stdout().to_owned(), span)))
}

///|
fn effect_failure(message : String, span : @source.Span) -> EvaluationError {
  Builtin(Failure(message~), span~)
}

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
        "failed to parse `" + count_text + "` as positive integer",
        span,
      )
  }
  if count < 0 {
    raise effect_failure("choose count must not be negative", span)
  }
  let alphabet_text = expect_string("choose", arguments, 1, span)
  let alphabet = alphabet_text.to_array()
  if alphabet.is_empty() {
    raise effect_failure("empty alphabet", span)
  }
  let unique : Set[Char] = Set([])
  for character in alphabet {
    if unique.contains(character) {
      raise effect_failure(
        "alphabet contains repeated character `" + character.to_string() + "`",
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
  let mut active = terminal.color_supported()
  let codes : Array[String] = []
  for style in styles {
    match style {
      "stdout" => active = active && terminal.stdout_is_terminal()
      "stderr" => active = active && terminal.stderr_is_terminal()
      "command" => codes.push("1")
      "error" => codes.push("31;1")
      "warning" => codes.push("33;1")
      _ =>
        match style_code(style) {
          Some(code) => codes.push(code)
          None => raise effect_failure("invalid style: `" + style + "`", span)
        }
    }
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
fn[T : @host.HostFs + @host.HostEnv + @host.HostPlatform] which_value(
  host : T,
  executable : String,
  context : EvaluationContext,
  span : @source.Span,
) -> String raise EvaluationError {
  if executable == "" {
    return ""
  }
  let cwd = require_context_path("cwd", context.cwd, span)
  if executable.contains("/") || executable.contains("\\") {
    let candidate = resolve_context_path(context, executable, span)
    let exists = @host.HostFs::file_exists(host, candidate) catch {
      error => raise Host(error, span~)
    }
    return if exists { candidate.as_string() } else { "" }
  }
  let path = @host.HostEnv::env_get(host, "PATH") catch {
    error => raise Host(error, span~)
  }
  let platform = @host.HostPlatform::platform_info(host) catch {
    error => raise Host(error, span~)
  }
  let separator = match platform.operating_system() {
    Windows => ";"
    _ => ":"
  }
  let extensions : Array[String] = match platform.operating_system() {
    Windows => ["", ".exe", ".cmd", ".bat", ".com"]
    _ => [""]
  }
  for directory in path.unwrap_or("").split(separator) {
    let base = if directory.length() == 0 {
      cwd
    } else {
      @path.PathValue::new(directory.to_owned(), cwd.flavor()) catch {
        _ => continue
      }
    }
    for extension in extensions {
      let child = @path.PathValue::new(executable + extension, cwd.flavor()) catch {
        _ => continue
      }
      let candidate = base.join(child) catch { _ => continue }
      let exists = @host.HostFs::file_exists(host, candidate) catch {
        error => raise Host(error, span~)
      }
      if exists {
        return candidate.as_string()
      }
    }
  }
  ""
}

///|
/// Invoke a builtin using explicit invocation facts and host capabilities.
pub fn[
  T : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] call_non_process_effect_with_context(
  host : T,
  requested : String,
  arguments : Array[Value],
  context : EvaluationContext,
  span : @source.Span,
) -> Value raise EvaluationError {
  let name = validate_effect_arity(requested, arguments, span)
  match context_builtin(name, arguments, context, span) {
    Some(value) => return value
    None => ()
  }
  match name {
    "arch" => {
      let platform = @host.HostPlatform::platform_info(host) catch {
        error => raise Host(error, span~)
      }
      String(platform.architecture())
    }
    "os" | "os_family" => {
      let platform = @host.HostPlatform::platform_info(host) catch {
        error => raise Host(error, span~)
      }
      let value = match platform.operating_system() {
        Linux => if name == "os_family" { "unix" } else { "linux" }
        Macos => if name == "os_family" { "unix" } else { "macos" }
        Windows => "windows"
        Other(value) => value
      }
      String(value)
    }
    "env" | "env_var" =>
      env_value(
        host,
        name,
        arguments[0],
        if name == "env" && arguments.length() == 2 {
          Some(arguments[1])
        } else {
          None
        },
        span,
      )
    "env_var_or_default" =>
      env_value(host, name, arguments[0], Some(arguments[1]), span)
    "absolute_path" => abort("handled by context builtin")
    "canonicalize" => {
      let raw = expect_string(name, arguments, 0, span)
      let path = resolve_context_path(context, raw, span)
      let canonical = @host.HostFs::canonicalize(host, path) catch {
        error => raise Host(error, span~)
      }
      String(canonical.as_string())
    }
    "read" => {
      let raw = expect_string(name, arguments, 0, span)
      let path = resolve_context_path(context, raw, span)
      let bytes = @host.HostFs::read_file(host, path) catch {
        error => raise Host(error, span~)
      }
      String(bytes_text(bytes, span))
    }
    "sha256_file" => {
      let raw = expect_string(name, arguments, 0, span)
      let path = resolve_context_path(context, raw, span)
      let hasher = @builtin.Sha256Hasher::new()
      @host.stream_file(host, path, fn(bytes) { hasher.update(bytes) }) catch {
        error => raise Host(error, span~)
      }
      String(hasher.finalize())
    }
    "blake3_file" => {
      let raw = expect_string(name, arguments, 0, span)
      let path = resolve_context_path(context, raw, span)
      let hasher = @builtin.Blake3Hasher::new()
      @host.stream_file(host, path, fn(bytes) { hasher.update(bytes) }) catch {
        error => raise Host(error, span~)
      }
      String(hasher.finalize())
    }
    "path_exists" => {
      let raw = expect_string(name, arguments, 0, span)
      if raw == "" {
        return Bool(false)
      }
      let path = resolve_context_path(context, raw, span)
      Bool(
        @host.HostFs::file_exists(host, path) catch {
          error => raise Host(error, span~)
        },
      )
    }
    "write" => {
      let raw = expect_string(name, arguments, 0, span)
      let contents = expect_string(name, arguments, 1, span)
      let path = resolve_context_path(context, raw, span)
      @host.HostFs::write_file(host, path, @utf8.encode(contents)) catch {
        error => raise Host(error, span~)
      }
      String("")
    }
    "now_millis" => {
      let value = @host.HostClock::now_millis(host) catch {
        error => raise Host(error, span~)
      }
      String(value.to_string())
    }
    "datetime" | "datetime_utc" => {
      let value = @host.HostClock::now_millis(host) catch {
        error => raise Host(error, span~)
      }
      let format = expect_string(name, arguments, 0, span)
      String(
        format_datetime(
          value,
          if name == "datetime_utc" {
            0
          } else {
            require_context_int(
              "utc_offset_seconds",
              context.utc_offset_seconds,
              span,
            )
          },
          format,
          span,
        ),
      )
    }
    "choose" => choose_value(host, arguments, span)
    "uuid" => {
      let bytes = @host.HostRandom::random_bytes(host, 16) catch {
        error => raise Host(error, span~)
      }
      if bytes.length() != 16 {
        raise effect_failure(
          "random host returned an invalid UUID byte count", span,
        )
      }
      String(uuid_text(bytes))
    }
    "shell" => raise EffectRequired(effect="process", span~)
    "style" => style_value(host, arguments, span)
    "which" => {
      let executable = expect_string(name, arguments, 0, span)
      String(which_value(host, executable, context, span))
    }
    "require" => {
      let executable = expect_string(name, arguments, 0, span)
      let path = which_value(host, executable, context, span)
      if path == "" {
        raise effect_failure(
          "could not find executable `" + executable + "`",
          span,
        )
      }
      String(path)
    }
    _ =>
      @builtin.call(name, arguments) catch {
        error => raise Builtin(error, span~)
      }
  }
}

///|
/// Invoke an effectful builtin using a synchronous process capability.
pub fn[
  T : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostProcess + @host.HostPlatform + @host.HostTerminal,
] call_effect_with_context(
  host : T,
  requested : String,
  arguments : Array[Value],
  context : EvaluationContext,
  span : @source.Span,
) -> Value raise EvaluationError {
  if @builtin.canonical_name(requested) == "shell" {
    call_shell_effect(
      host,
      arguments,
      context,
      EffectShell::new("sh", ["-cu"]),
      span,
    )
  } else {
    call_non_process_effect_with_context(
      host, requested, arguments, context, span,
    )
  }
}

///|
/// Backwards-compatible cwd-only effect entry point. Context-only facts not
/// derivable from cwd remain explicit `MissingContext` errors.
pub fn[
  T : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostProcess + @host.HostPlatform + @host.HostTerminal,
] call_effect(
  host : T,
  name : String,
  arguments : Array[Value],
  cwd : @path.PathValue,
  span : @source.Span,
) -> Value raise EvaluationError {
  call_effect_with_context(
    host,
    name,
    arguments,
    EvaluationContext::new(
      cwd~,
      invocation_directory=cwd,
      invocation_directory_native=cwd,
    ),
    span,
  )
}

///|
pub fn[
  T : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostProcess + @host.HostPlatform + @host.HostTerminal,
] evaluate_backtick(
  host : T,
  command : String,
  cwd : @path.PathValue,
  span : @source.Span,
) -> Value raise EvaluationError {
  call_effect(host, "shell", [String(command)], cwd, span)
}

///|
pub fn[T : @host.HostProcess] evaluate_backtick_with_shell(
  host : T,
  command : String,
  context : EvaluationContext,
  shell : EffectShell,
  span : @source.Span,
  quiet? : Bool = false,
) -> Value raise EvaluationError {
  call_shell_effect(host, [String(command)], context, shell, span, quiet~)
}
