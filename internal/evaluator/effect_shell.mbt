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
  { program, arguments: arguments.copy(), }
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
fn shell_takes_name(program : String) -> Bool {
  let name = program
    .replace_all(old="\\", new="/")
    .split("/")
    .last()
    .unwrap_or(program[:])
    .to_lower()
  name != "cmd" &&
  name != "cmd.exe" &&
  name != "powershell" &&
  name != "powershell.exe" &&
  name != "pwsh" &&
  name != "pwsh.exe"
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
fn configure_effect_environment(
  spec : @host.CommandSpec,
  context : EvaluationContext,
  span : @source.Span,
) -> Unit raise EvaluationError {
  guard context.process_environment is Some(entries) else { return }
  spec.set_inherit_environment(false)
  for entry in entries {
    spec.add_environment(entry.0, entry.1) catch {
      error => raise Host(error, span~)
    }
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
  shell_function? : Bool = true,
) -> Value raise EvaluationError {
  let name = validate_effect_arity("shell", arguments, span)
  let command = expect_string(name, arguments, 0, span)
  let shell_arguments = shell.arguments().to_owned()
  shell_arguments.push(command)
  if shell_function && shell_takes_name(shell.program()) {
    shell_arguments.push(command)
    for argument in arguments[1:] {
      shell_arguments.push(expect_string(name, [argument], 0, span))
    }
  }
  let spec = @host.CommandSpec::new(shell.program(), shell_arguments) catch {
    error => raise Host(error, span~)
  }
  let cwd = require_context_path("cwd", context.cwd, span)
  spec.set_cwd(cwd)
  configure_effect_environment(spec, context, span)
  spec.set_inherit_stdin(true)
  spec.set_stdout(Capture)
  spec.set_stderr(if quiet { Discard } else { Inherit })
  let output = @host.HostProcess::run_process(host, spec) catch {
    error => raise Host(error, span~)
  }
  match output.termination() {
    Exited(0) => ()
    Exited(code) =>
      if shell_function {
        raise ProcessFailure(code~, span~)
      } else {
        raise BacktickFailure(code~, span~)
      }
    Signaled(signal) | Interrupted(signal) =>
      raise ProcessSignaled(signal~, span~)
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
  shell_function? : Bool = true,
) -> Value raise EvaluationError {
  let name = validate_effect_arity("shell", arguments, span)
  let command = expect_string(name, arguments, 0, span)
  let shell_arguments = shell.arguments().to_owned()
  shell_arguments.push(command)
  if shell_function && shell_takes_name(shell.program()) {
    shell_arguments.push(command)
    for argument in arguments[1:] {
      shell_arguments.push(expect_string(name, [argument], 0, span))
    }
  }
  let spec = @host.CommandSpec::new(shell.program(), shell_arguments) catch {
    error => raise Host(error, span~)
  }
  spec.set_cwd(require_context_path("cwd", context.cwd, span))
  configure_effect_environment(spec, context, span)
  spec.set_inherit_stdin(true)
  spec.set_stdout(Capture)
  spec.set_stderr(if quiet { Discard } else { Inherit })
  let output = @host.HostAsyncProcess::run_process_async(host, spec) catch {
    error =>
      if shell_function {
        raise Host(error, span~)
      } else {
        raise effect_failure(
          "backtick could not be run because just could not find the shell: " +
          Repr(error).to_string(),
          span,
        )
      }
  }
  match output.termination() {
    Exited(0) => ()
    Exited(code) =>
      if shell_function {
        raise ProcessFailure(code~, span~)
      } else {
        raise BacktickFailure(code~, span~)
      }
    Signaled(signal) | Interrupted(signal) =>
      raise ProcessSignaled(signal~, span~)
  }
  String(strip_one_line_ending(bytes_text(output.stdout().to_owned(), span)))
}

///|
fn effect_failure(message : String, span : @source.Span) -> EvaluationError {
  Builtin(Failure(message~), span~)
}

///|
