///|
/// Native/wasm1 process leaf backed by `moonbitlang/async/process`.
pub struct ProcessAdapter {
  output_mutex : @async.Mutex
}

///|
/// Captured output is retained so the runtime can flush parallel tasks in
/// deterministic invocation order. Bound each stream to keep one child from
/// exhausting the runtime while its pipe is drained with backpressure.
const MAX_CAPTURED_STREAM_BYTES : Int = 16 * 1024 * 1024

///|
fn[X] stdio_is_regular(fd : X) -> Bool {
  // async keeps fd classification internal. Unknown inherited streams must
  // remain direct streams rather than being reclassified by a MoonJust FFI.
  ignore(fd)
  false
}

///|
pub fn ProcessAdapter::new() -> ProcessAdapter {
  { output_mutex: Mutex(), }
}

///|
let process_resolution_mutex : @async.Mutex = Mutex()

///|
let process_resolution_cache : Map[String, String] = Map([])

///|
priv enum ObservedProcess {
  Managed(@async_process.Process)
}

///|
priv enum WaitOutcome {
  Completed(Int)
  Cancelled
}

///|
async fn[X] spawn_observed_process(
  group : @async.TaskGroup[X],
  program : String,
  arguments : ArrayView[String],
  environment : Map[String, String],
  inherit_environment : Bool,
  stdin : &@async_process.ProcessInput,
  stdout : &@async_process.ProcessOutput,
  stderr : &@async_process.ProcessOutput,
  cwd : String,
) -> ObservedProcess {
  let process = @async_process.spawn(
    group,
    program,
    arguments,
    extra_env=environment,
    inherit_env=inherit_environment,
    stdin~,
    stdout~,
    stderr~,
    cwd~,
    cancel_handler=@async_process.graceful_cancel(timeout=5000),
    no_wait=true,
  )
  Managed(process)
}

///|
#warnings("-fragile_catch_all")
async fn ObservedProcess::wait(self : ObservedProcess) -> WaitOutcome {
  let Managed(process) = self
  let status = process.wait() catch {
    error => {
      if @async.is_cancellation_error(error) {
        process.cancel()
        ignore(
          @async.protect_from_cancel(() => {
            try process.wait() catch {
              _ => 0
            } noraise {
              value => value
            }
          }),
        )
        return Cancelled
      }
      raise error
    }
  }
  Completed(status)
}

///|
fn ObservedProcess::cancel(self : ObservedProcess) -> Unit {
  let Managed(process) = self
  process.cancel()
}

///|
async fn write_stdio(
  mutex : @async.Mutex,
  stream : @host.OutputStream,
  bytes : Bytes,
) -> Int raise @host.HostError {
  try mutex.acquire() catch {
    _ => raise InvalidInput("runtime output lock failed")
  } noraise {
    _ => ()
  }
  defer mutex.release()
  try {
    let mut offset = 0
    while offset < bytes.length() {
      let written = match stream {
        Stdout =>
          @stdio.stdout.write_once(bytes, offset~, len=bytes.length() - offset)
        Stderr =>
          @stdio.stderr.write_once(bytes, offset~, len=bytes.length() - offset)
      }
      if written <= 0 {
        raise @host.HostError::InvalidInput("failed to write runtime output")
      }
      offset += written
    }
    offset
  } catch {
    _ => raise InvalidInput("failed to write runtime output")
  }
}

///|
pub impl @host.HostAsyncOutput for ProcessAdapter with fn write_output(
  self : ProcessAdapter,
  stream : @host.OutputStream,
  bytes : Bytes,
) -> Int raise @host.HostError {
  write_stdio(self.output_mutex, stream, bytes)
}

///|
fn signal_from_number(number : Int) -> @host.SignalKind {
  match number {
    1 => Hangup
    2 => Interrupt
    15 => Terminate
    value => OtherSignal(value)
  }
}

///|
fn signal_from_status(status : Int) -> @host.SignalKind {
  signal_from_number(-status)
}

///|
fn environment_map(command : @host.CommandSpec) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for entry in command.environment() {
    result[entry.0] = entry.1
  }
  result
}

///|
fn windows_program_candidates(
  program : String,
  path : String,
  pathext : String,
) -> Array[String] {
  let bases = [program]
  let has_separator = program.contains("/") || program.contains("\\")
  let unix_absolute = program.has_prefix("/")
  if !has_separator || unix_absolute {
    let name = if unix_absolute {
      program
      .replace_all(old="\\", new="/")
      .split("/")
      .last()
      .unwrap_or(program[:])
    } else {
      program
    }
    for raw_directory in path.split(";") {
      let directory = raw_directory.trim(chars="\"")
      bases.push(
        if directory.is_empty() {
          name.to_owned()
        } else if directory.has_suffix("/") || directory.has_suffix("\\") {
          directory.to_owned() + name.to_owned()
        } else {
          directory.to_owned() + "\\" + name.to_owned()
        },
      )
    }
  }
  let basename = program
    .replace_all(old="\\", new="/")
    .split("/")
    .last()
    .unwrap_or(program[:])
  if basename.contains(".") {
    return bases
  }
  let candidates : Array[String] = []
  for base in bases {
    for raw_extension in pathext.split(";") {
      let extension = raw_extension.trim()
      if extension.is_empty() {
        continue
      }
      if extension.has_prefix(".") {
        candidates.push(base + extension.to_owned())
      }
    }
  }
  candidates
}

///|
#warnings("-unused_value")
fn windows_batch_command(
  program : String,
  arguments : ArrayView[String],
  windows : Bool,
) -> (String, Array[String]) {
  let lower = program.to_lower()
  if !windows || (!lower.has_suffix(".bat") && !lower.has_suffix(".cmd")) {
    return (program, arguments.to_owned())
  }
  let command_arguments = ["/d", "/s", "/c", program]
  for argument in arguments {
    command_arguments.push(argument)
  }
  ("cmd.exe", command_arguments)
}

///|
fn windows_batch_body(command : String) -> String {
  guard command.trim().to_lower().has_prefix("for ") else { return command }
  let mut variable : String? = None
  if command.length() >= 2 {
    for index in 0..<(command.length() - 1) {
      if command.unsafe_get(index) == '%' &&
        command.unsafe_get(index + 1) != '%' {
        variable = Some(command[index:index + 2].to_owned())
        break
      }
    }
  }
  match variable {
    Some(value) => command.replace_all(old=value, new="%" + value)
    None => command
  }
}

///|
/// Commands without cmd metacharacters have identical command-line and batch
/// parsing, so they do not need a temporary wrapper file.
fn windows_direct_command_safe(command : String) -> Bool {
  let lower = command.to_lower()
  if command.is_empty() ||
    command.contains("\r") ||
    command.contains("\n") ||
    lower.contains(".cmd") ||
    lower.contains(".bat") {
    return false
  }
  for character in command {
    if character.is_ascii_alphabetic() ||
      character.is_ascii_digit() ||
      character == ' ' ||
      character == '_' ||
      character == '-' ||
      character == '.' ||
      character == '/' ||
      character == '\\' ||
      character == ':' {
      continue
    }
    return false
  }
  true
}

///|
fn windows_known_shell_noop_command(
  program : String,
  arguments : ArrayView[String],
) -> Bool {
  let basename = program
    .replace_all(old="\\", new="/")
    .split("/")
    .last()
    .unwrap_or(program[:])
    .to_lower()
  if basename != "cmd" && basename != "cmd.exe" {
    return false
  }
  if arguments.length() != 4 {
    return false
  }
  arguments[0] == "/d" &&
  arguments[1] == "/s" &&
  arguments[2] == "/c" &&
  arguments[3] == ":"
}

///|
fn windows_known_shell_noop(
  program : String,
  arguments : ArrayView[String],
) -> Bool {
  windows_process_runtime() &&
  windows_known_shell_noop_command(program, arguments)
}

///|
/// A direct `cmd /c` command leaves an undefined `%NAME%` reference literal,
/// while a batch file expands it to an empty string. Double the delimiters for
/// undefined names so the temporary wrapper preserves command-line semantics.
fn windows_environment_contains(
  name : String,
  environment : ArrayView[(String, String)],
  inherit_environment : Bool,
) -> Bool {
  let normalized = name.to_lower()
  for entry in environment {
    if entry.0.to_lower() == normalized {
      return true
    }
  }
  inherit_environment && @env.get_env_var(name) is Some(_)
}

///|
fn windows_escape_undefined_variables(
  command : String,
  environment : ArrayView[(String, String)],
  inherit_environment : Bool,
) -> String {
  let characters = command.to_array()
  let output = StringBuilder()
  let mut index = 0
  while index < characters.length() {
    if characters[index] == '%' &&
      index + 1 < characters.length() &&
      characters[index + 1] != '%' {
      let mut end = index + 1
      while end < characters.length() && characters[end] != '%' {
        end += 1
      }
      if end < characters.length() {
        let name = String::from_array(characters[index + 1:end])
        let mut valid = !name.is_empty()
        for character in name {
          if !character.is_ascii_alphabetic() &&
            !character.is_ascii_digit() &&
            character != '_' {
            valid = false
            break
          }
        }
        if valid &&
          !windows_environment_contains(name, environment, inherit_environment) {
          output.write_string("%%")
          output.write_string(name)
          output.write_string("%%")
          index = end + 1
          continue
        }
      }
    }
    output.write_char(characters[index])
    index += 1
  }
  output.to_string()
}

///|
fn process_random_suffix() -> String raise @host.HostError {
  guard @env.rand(12) is Some(bytes) else {
    raise CapabilityUnavailable(Random)
  }
  let digits = "0123456789abcdef"
  let builder = StringBuilder()
  for byte in bytes {
    builder.write_char(digits.get_char((byte.to_int() >> 4) & 15).unwrap())
    builder.write_char(digits.get_char(byte.to_int() & 15).unwrap())
  }
  builder.to_string()
}

///|
