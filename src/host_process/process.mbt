///|
/// Native/wasm1 process leaf backed by `moonbitlang/async/process`.
pub struct ProcessAdapter {
  output_mutex : @async.Mutex
}

///|
/// Captured output is retained so the runtime can flush parallel tasks in
/// deterministic invocation order. Bound each stream to keep one child from
/// exhausting the executor while its pipe is drained with backpressure.
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
  Managed(@process.Process)
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
  stdin : &@process.ProcessInput,
  stdout : &@process.ProcessOutput,
  stderr : &@process.ProcessOutput,
  cwd : String,
) -> ObservedProcess {
  let process = @process.spawn(
    group,
    program,
    arguments,
    extra_env=environment,
    inherit_env=inherit_environment,
    stdin~,
    stdout~,
    stderr~,
    cwd~,
    cancel_handler=@process.graceful_cancel(timeout=5000),
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
async fn materialize_windows_command(
  program : String,
  arguments : ArrayView[String],
  cwd : String,
  environment : ArrayView[(String, String)],
  inherit_environment : Bool,
) -> (String, Array[String], String?) raise @host.HostError {
  if !windows_process_runtime() {
    return (program, arguments.to_owned(), None)
  }
  let lower = program.to_lower()
  let is_batch = lower.has_suffix(".cmd") || lower.has_suffix(".bat")
  let basename = program
    .replace_all(old="\\", new="/")
    .split("/")
    .last()
    .unwrap_or(program[:])
    .to_lower()
  let is_cmd = basename == "cmd.exe" || basename == "cmd"
  let mut body : String? = None
  let mut command_index : Int? = None
  if is_cmd {
    for index, argument in arguments {
      let lower_argument = argument.to_lower()
      if lower_argument == "/c" || lower_argument == "/command" {
        if index + 1 < arguments.length() {
          body = Some(arguments[index + 1])
          command_index = Some(index)
          break
        }
      }
    }
  } else if is_batch {
    body = Some(
      "@echo off\r\ncall \"" +
      program.replace_all(old="\"", new="\"\"") +
      "\" %*\r\nexit /b %errorlevel%\r\n",
    )
  }
  guard body is Some(command) else {
    return (program, arguments.to_owned(), None)
  }
  if is_cmd &&
    command_index is Some(index) &&
    index + 2 == arguments.length() &&
    windows_direct_command_safe(command) {
    return (program, arguments.to_owned(), None)
  }
  let command_lower = command.to_lower()
  let command_is_batch_path = (
      command_lower.has_suffix(".cmd") || command_lower.has_suffix(".bat")
    ) &&
    (try @async_fs.kind(command) catch {
      _ => false
    } noraise {
      Regular => true
      _ => false
    })
  let command_for_batch = windows_escape_undefined_variables(
    windows_batch_body(command),
    environment,
    inherit_environment,
  )
  let script = if is_batch {
    command
  } else if command_is_batch_path {
    "@echo off\r\ncall \"" +
    command.replace_all(old="\"", new="\"\"") +
    "\"\r\nexit /b %errorlevel%\r\n"
  } else {
    "@" + command_for_batch + "\r\n"
  }
  let filename = ".moonjust-cmd-" + process_random_suffix() + ".cmd"
  let path = if cwd == "." || cwd.is_empty() {
    filename
  } else if cwd.has_suffix("\\") || cwd.has_suffix("/") {
    cwd + filename
  } else {
    cwd + "\\" + filename
  }
  @async_fs.write_file(
    path,
    @utf8.encode(script),
    create_mode=CreateNew,
    permission=0o600,
  ) catch {
    _ => raise InvalidInput("failed to create temporary Windows command script")
  }
  let rewritten : Array[String] = []
  if is_batch {
    rewritten.push("/d")
    rewritten.push("/s")
    rewritten.push("/c")
    rewritten.push(path)
    for argument in arguments {
      rewritten.push(argument)
    }
  } else {
    let index = command_index.unwrap()
    rewritten.push("/d")
    rewritten.push("/s")
    for argument in arguments[:index] {
      let lower_argument = argument.to_lower()
      if lower_argument != "/d" && lower_argument != "/s" {
        rewritten.push(argument)
      }
    }
    rewritten.push("/c")
    rewritten.push(path)
    for argument in arguments[index + 2:] {
      rewritten.push(argument)
    }
  }
  ("cmd.exe", rewritten, Some(path))
}

///|
async fn remove_windows_command_script(path : String) -> Unit {
  try @async_fs.remove(path) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
async fn windows_native_program(
  program : String,
  cwd : String,
) -> String noraise {
  if !windows_process_runtime() || !program.contains("/") {
    return program
  }
  let cygpath = @env.get_env_var("JUST_CYGPATH").unwrap_or("cygpath")
  let (status, stdout, _) = try
    @process.collect_output(cygpath, ["--windows", program], cwd~)
  catch {
    _ => return program
  } noraise {
    value => value
  }
  if status != 0 {
    return program
  }
  let translated = try stdout.text() catch {
    _ => return program
  } noraise {
    value => value.trim_end().to_owned()
  }
  if translated.is_empty() {
    program
  } else {
    translated
  }
}

///|
#cfg(platform="windows")
fn windows_process_runtime() -> Bool {
  true
}

///|
#cfg(not(platform="windows"))
fn windows_process_runtime() -> Bool {
  @env.get_env_var("MOONJUST_OS") == Some("windows")
}

///|
async fn resolve_process_program_with_context(
  program : String,
  cwd : String,
  path : String,
  pathext : String,
) -> String {
  if !windows_process_runtime() {
    return program
  }
  let program = windows_native_program(program, cwd)
  for candidate in windows_program_candidates(program, path, pathext) {
    let regular = try @async_fs.kind(candidate) catch {
      _ => false
    } noraise {
      Regular => true
      _ => false
    }
    if regular {
      return candidate
    }
  }
  program
}

///|
async fn resolve_process_program(program : String, cwd : String) -> String {
  resolve_process_program_with_context(
    program,
    cwd,
    @env.get_env_var("PATH").unwrap_or(""),
    @env.get_env_var("PATHEXT").unwrap_or(".COM;.EXE;.BAT;.CMD"),
  )
}

///|
fn windows_resolution_key(
  program : String,
  cwd : String,
  path : String,
  pathext : String,
  cygpath : String,
  shell_mode? : String = "auto",
) -> String {
  program +
  "\u{0000}" +
  cwd +
  "\u{0000}" +
  path +
  "\u{0000}" +
  pathext +
  "\u{0000}" +
  cygpath +
  "\u{0000}" +
  shell_mode
}

///|
fn windows_shell_mode(
  program : String,
  arguments : ArrayView[String],
) -> String {
  let basename = program
    .replace_all(old="\\", new="/")
    .split("/")
    .last()
    .unwrap_or(program[:])
    .to_lower()
  if basename == "cmd" || basename == "cmd.exe" {
    if arguments.contains("/c") || arguments.contains("/command") {
      "cmd-command"
    } else {
      "cmd"
    }
  } else if basename.has_suffix(".cmd") || basename.has_suffix(".bat") {
    "batch"
  } else {
    "direct"
  }
}

///|
async fn resolve_process_program_cached(
  program : String,
  cwd : String,
  arguments : ArrayView[String],
) -> String {
  if !windows_process_runtime() {
    return program
  }
  let path = @env.get_env_var("PATH").unwrap_or("")
  let pathext = @env.get_env_var("PATHEXT").unwrap_or(".COM;.EXE;.BAT;.CMD")
  let key = windows_resolution_key(
    program,
    cwd,
    path,
    pathext,
    @env.get_env_var("JUST_CYGPATH").unwrap_or("cygpath"),
    shell_mode=windows_shell_mode(program, arguments),
  )
  let acquired = try process_resolution_mutex.acquire() catch {
    _ => false
  } noraise {
    _ => true
  }
  if !acquired {
    return resolve_process_program(program, cwd)
  }
  defer process_resolution_mutex.release()
  match process_resolution_cache.get(key) {
    Some(value) => value
    None => {
      let resolved = resolve_process_program(program, cwd)
      if process_resolution_cache.length() >= 256 {
        process_resolution_cache.clear()
      }
      process_resolution_cache[key] = resolved
      resolved
    }
  }
}

///|
async fn read_bounded_process_output(
  output_mutex : @async.Mutex,
  reader : @process.ReadFromProcess,
  limit : Int,
  retain : Bool,
  process : ObservedProcess,
  forward : @host.OutputStream?,
) -> (Bytes, Bool) {
  defer reader.close()
  let output = Buffer(
    size_hint=if retain { Int::min(limit, 64 * 1024) } else { 0 },
  )
  while true {
    let max_length = if retain {
      Int::min(64 * 1024, Int::max(limit - output.length(), 0) + 1)
    } else {
      64 * 1024
    }
    guard reader.read_some(max_len=max_length) is Some(chunk) else { break }
    match forward {
      Some(stream) => {
        ignore(write_stdio(output_mutex, stream, chunk))
        continue
      }
      None => ()
    }
    if !retain {
      continue
    }
    let remaining = Int::max(limit - output.length(), 0)
    if chunk.length() > remaining {
      if remaining > 0 {
        output.write_bytes(chunk[:remaining])
      }
      process.cancel()
      return (output.to_bytes(), true)
    }
    output.write_bytes(chunk)
  }
  (output.to_bytes(), false)
}

///|
fn process_result(
  command : @host.CommandSpec,
  outcome : WaitOutcome,
  stdout : Bytes,
  stderr : Bytes,
) -> @host.ProcessResult {
  let captured_stdout = if command.stdout() == Capture { stdout } else { b"" }
  let captured_stderr = if command.stderr() == Capture { stderr } else { b"" }
  match outcome {
    Cancelled =>
      @host.ProcessResult::from_interruption(
        Interrupt,
        captured_stdout,
        captured_stderr,
      )
    Completed(status) if status < 0 =>
      @host.ProcessResult::from_signal(
        signal_from_status(status),
        captured_stdout,
        captured_stderr,
      )
    Completed(status) =>
      @host.ProcessResult::new(status, captured_stdout, captured_stderr)
  }
}

///|
async fn run_process_with_output_limit(
  command : @host.CommandSpec,
  output_limit : Int,
  output_mutex? : @async.Mutex = Mutex(),
) -> @host.ProcessResult raise @host.HostError {
  if output_limit < 0 {
    raise InvalidInput("captured process output limit must be non-negative")
  }
  let cwd = command.cwd().map(fn(path) { path.as_string() }).unwrap_or(".")
  let resolved_program = try
    resolve_process_program_cached(command.program(), cwd, command.arguments())
  catch {
    error => raise InvalidInput(error.to_string())
  } noraise {
    value => value
  }
  if windows_known_shell_noop(resolved_program, command.arguments()) {
    return process_result(command, Completed(0), b"", b"")
  }
  let collected = try
    @async.with_task_group() <| reader_group => {
      let (wrapped_program, wrapped_arguments, temporary_script) = materialize_windows_command(
        resolved_program,
        command.arguments(),
        cwd,
        command.environment(),
        command.inherits_environment(),
      )
      let program = wrapped_program
      let arguments = wrapped_arguments
      let (stdout_reader, stdout_target) = @process.read_from_process()
      let (stderr_reader, stderr_target) = @process.read_from_process()
      let stdout_regular = if command.stdout() == Inherit {
        stdio_is_regular(@stdio.stdout.fd())
      } else {
        false
      }
      let stderr_regular = if command.stderr() == Inherit {
        stdio_is_regular(@stdio.stderr.fd())
      } else {
        false
      }
      let pipe_stdout = command.stdout() != Inherit || stdout_regular
      let pipe_stderr = command.stderr() != Inherit || stderr_regular
      let merge_regular = stdout_regular &&
        stderr_regular &&
        @stdio.stdout.fd() == @stdio.stderr.fd()
      let (outcome, stdout_task, stderr_task) = @async.with_task_group() <| child_group => {
        match temporary_script {
          Some(path) =>
            child_group.add_defer(() => remove_windows_command_script(path))
          None => ()
        }
        let child_stdin = if command.inherits_stdin() {
          None
        } else {
          let (child_stdin, writer) = @process.write_to_process()
          child_group.spawn_bg(() => {
            defer writer.close()
            if !command.stdin().is_empty() {
              try writer.write(command.stdin()) catch {
                _ => ()
              } noraise {
                _ => ()
              }
            }
          })
          Some(child_stdin)
        }
        let child_stdout = if pipe_stdout {
          stdout_target
        } else {
          @stdio.stdout
        }
        let child_stderr = if merge_regular {
          stdout_target
        } else if pipe_stderr {
          stderr_target
        } else {
          @stdio.stderr
        }
        let environment = environment_map(command)
        let process = if command.inherits_stdin() {
          spawn_observed_process(
            child_group,
            program,
            arguments,
            environment,
            command.inherits_environment(),
            @stdio.stdin,
            child_stdout,
            child_stderr,
            cwd,
          )
        } else {
          spawn_observed_process(
            child_group,
            program,
            arguments,
            environment,
            command.inherits_environment(),
            child_stdin.unwrap(),
            child_stdout,
            child_stderr,
            cwd,
          )
        }
        let stdout_task = if !pipe_stdout {
          stdout_reader.close()
          None
        } else {
          Some(
            reader_group.spawn(() => {
              read_bounded_process_output(
                output_mutex,
                stdout_reader,
                output_limit,
                command.stdout() == Capture,
                process,
                if command.stdout() == Inherit {
                  Some(Stdout)
                } else {
                  None
                },
              )
            }),
          )
        }
        let stderr_task = if merge_regular || !pipe_stderr {
          stderr_reader.close()
          None
        } else {
          Some(
            reader_group.spawn(() => {
              read_bounded_process_output(
                output_mutex,
                stderr_reader,
                output_limit,
                command.stderr() == Capture,
                process,
                if command.stderr() == Inherit {
                  Some(Stderr)
                } else {
                  None
                },
              )
            }),
          )
        }
        let outcome = process.wait()
        (outcome, stdout_task, stderr_task)
      }
      let (stdout, stdout_limited) = match stdout_task {
        Some(reader) => reader.wait()
        None => (b"", false)
      }
      let (stderr, stderr_limited) = match stderr_task {
        Some(reader) => reader.wait()
        None => (b"", false)
      }
      (outcome, stdout, stderr, stdout_limited, stderr_limited)
    }
  catch {
    @host.HostError::InvalidInput(message) => raise InvalidInput(message)
    @host.HostError::PermissionDenied(capability, detail~) =>
      raise PermissionDenied(capability, detail~)
    error => {
      let detail = error.to_string()
      if detail.contains("Permission denied") {
        raise PermissionDenied(
          Process,
          detail="Permission denied (os error 13)",
        )
      }
      if detail.contains("No such file or directory") {
        raise InvalidInput("No such file or directory (os error 2)")
      }
      raise InvalidInput(detail)
    }
  } noraise {
    value => value
  }
  let (outcome, stdout, stderr, stdout_limited, stderr_limited) = collected
  if stdout_limited || stderr_limited {
    raise InvalidInput(
      "process captured output exceeded the \{output_limit}-byte per-stream limit",
    )
  }
  process_result(command, outcome, stdout, stderr)
}

///|
pub impl @host.HostAsyncProcess for ProcessAdapter with fn run_process_async(
  self : ProcessAdapter,
  command : @host.CommandSpec,
) -> @host.ProcessResult raise @host.HostError {
  run_process_with_output_limit(
    command,
    MAX_CAPTURED_STREAM_BYTES,
    output_mutex=self.output_mutex,
  )
}
