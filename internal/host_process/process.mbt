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
#cfg(target="native")
extern "C" fn stdio_kind(fd : @types.Fd) -> Int = "moonjust_kind_of_fd"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn stdio_kind(fd : @types.Fd) -> Int = "moonbitlang/async" "fd_util/kind_of_fd"

///|
#cfg(all(target="native", not(platform="windows")))
const PROCESS_GROUP_TERM_TIMEOUT_MS : Int = 5000

///|
#cfg(all(target="native", not(platform="windows")))
const PROCESS_GROUP_POLL_MS : Int = 25

///|
#cfg(all(target="native", not(platform="windows")))
fn process_group_requested(inherit_stdin : Bool) -> Bool {
  if !process_group_boundary_is_enabled() {
    return false
  }
  if !inherit_stdin {
    return true
  }
  try stdio_kind(@stdio.stdin.fd()) != 2 catch {
    _ => false
  } noraise {
    value => value
  }
}

///|
#cfg(any(target="wasm", platform="windows"))
fn process_group_requested(_inherit_stdin : Bool) -> Bool {
  false
}

///|
#cfg(all(target="native", not(platform="windows")))
fn is_shell_program(program : String) -> Bool {
  let lower = program.to_lower()
  lower == "sh" ||
  lower == "bash" ||
  lower == "dash" ||
  lower == "zsh" ||
  lower == "ksh" ||
  lower == "fish" ||
  lower.has_suffix("/sh") ||
  lower.has_suffix("/bash") ||
  lower.has_suffix("/dash") ||
  lower.has_suffix("/zsh") ||
  lower.has_suffix("/ksh") ||
  lower.has_suffix("/fish")
}

///|
#cfg(all(target="native", not(platform="windows")))
async fn resolve_group_executable(
  executable : String,
  path : String,
  current_directory : String,
) -> String {
  if executable.contains("/") {
    return if executable.has_prefix("/") {
      executable
    } else {
      current_directory + "/" + executable
    }
  }
  for directory_view in path.split(":") {
    let directory = directory_view.to_owned()
    let candidate = if directory == "" {
      current_directory + "/" + executable
    } else {
      directory + "/" + executable
    }
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
  executable
}

///|
#cfg(all(target="native", not(platform="windows")))
async fn current_executable_for_group() -> String {
  resolve_group_executable(
    @env.args().get(0).unwrap_or("just"),
    @env.get_env_var("PATH").unwrap_or(""),
    @env.current_dir().unwrap_or("."),
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
fn grouped_environment(
  environment : Map[String, String],
) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for entry in environment {
    result[entry.0] = entry.1
  }
  result["MOONJUST_INTERNAL_PROCESS_GROUP"] = "1"
  result
}

///|
#cfg(all(target="native", not(platform="windows")))
async fn wait_for_process_group(
  process : @process.Process,
  pid : Int,
) -> Bool raise @host.HostError {
  let attempts = PROCESS_GROUP_TERM_TIMEOUT_MS / PROCESS_GROUP_POLL_MS
  for _ in 0..<attempts {
    let state = process_group_id(pid)
    if state == pid {
      return true
    }
    if state == 0 && process_group_alive(pid) {
      return true
    }
    if state < 0 {
      process.cancel()
      try process.wait() catch {
        _ => ()
      } noraise {
        _ => ()
      }
      raise InvalidInput("failed to establish an owned Unix process group")
    }
    let finished = try process.try_wait() catch {
      _ => None
    } noraise {
      value => value
    }
    if finished is Some(_) {
      return process_group_alive(pid)
    }
    try @async.sleep(PROCESS_GROUP_POLL_MS) catch {
      _ => raise InvalidInput("process-group readiness wait was cancelled")
    } noraise {
      _ => ()
    }
  }
  process.cancel()
  try process.wait() catch {
    _ => ()
  } noraise {
    _ => ()
  }
  raise InvalidInput("timed out establishing an owned Unix process group")
}

///|
#cfg(all(target="native", not(platform="windows")))
async fn cleanup_process_group(group : Int) -> Unit raise @host.HostError {
  let term = signal_process_group(group, 15)
  if term < 0 {
    raise InvalidInput("failed to terminate owned Unix process group")
  }
  let attempts = PROCESS_GROUP_TERM_TIMEOUT_MS / PROCESS_GROUP_POLL_MS
  for _ in 0..<attempts {
    if !process_group_alive(group) {
      return
    }
    try @async.sleep(PROCESS_GROUP_POLL_MS) catch {
      _ => raise InvalidInput("process-group cleanup wait was cancelled")
    } noraise {
      _ => ()
    }
  }
  let kill = signal_process_group(group, 9)
  if kill < 0 {
    raise InvalidInput("failed to kill owned Unix process group")
  }
  for _ in 0..<attempts {
    if !process_group_alive(group) {
      return
    }
    try @async.sleep(PROCESS_GROUP_POLL_MS) catch {
      _ => raise InvalidInput("process-group cleanup wait was cancelled")
    } noraise {
      _ => ()
    }
  }
  raise InvalidInput("owned Unix process group did not terminate")
}

///|
#cfg(all(target="native", not(platform="windows")))
async fn cleanup_process_group_protected(
  group : Int,
) -> Unit raise @host.HostError {
  try @async.protect_from_cancel(() => cleanup_process_group(group)) catch {
    @host.HostError::InvalidInput(message) => raise InvalidInput(message)
    _ => raise InvalidInput("protected Unix process-group cleanup failed")
  } noraise {
    _ => ()
  }
}

///|
pub fn ProcessAdapter::new() -> ProcessAdapter {
  { output_mutex: Mutex() }
}

///|
#cfg(all(target="native", not(platform="windows")))
priv enum ObservedProcess {
  Managed(process~ : @process.Process, pid~ : Int, process_group~ : Int?)
}

///|
#cfg(any(target="wasm", platform="windows"))
priv enum ObservedProcess {
  Managed(@process.Process)
}

///|
#cfg(all(target="native", not(platform="windows")))
async fn[X] spawn_observed_process(
  group : @async.TaskGroup[X],
  program : String,
  arguments : ArrayView[String],
  group_process : Bool,
  environment : Map[String, String],
  inherit_environment : Bool,
  stdin : &@process.ProcessInput,
  stdout : &@process.ProcessOutput,
  stderr : &@process.ProcessOutput,
  cwd : String,
) -> ObservedProcess {
  let grouped = group_process && is_shell_program(program)
  let (launch_program, launch_arguments, launch_environment) = if grouped {
    let helper_arguments = ["--moonjust-process-group-exec", program]
    for argument in arguments {
      helper_arguments.push(argument)
    }
    (
      current_executable_for_group(),
      helper_arguments,
      grouped_environment(environment),
    )
  } else {
    (program, arguments.to_owned(), environment)
  }
  let process = @process.spawn(
    group,
    launch_program,
    launch_arguments,
    extra_env=launch_environment,
    inherit_env=inherit_environment,
    stdin~,
    stdout~,
    stderr~,
    cwd~,
    cancel_handler=CancellationHandler(cancel_signal_child),
    no_wait=true,
  )
  let pid = process.pid
  let quoted : Array[String] = []
  quoted.push("\"" + program.replace_all(old="\"", new="\\\"") + "\"")
  for argument in arguments {
    quoted.push("\"" + argument.replace_all(old="\"", new="\\\"") + "\"")
  }
  let description = "cd \"" +
    cwd.replace_all(old="\"", new="\\\"") +
    "\" && " +
    quoted.join(" ")
  add_signal_child(pid, description)
  let process_group = if grouped {
    try wait_for_process_group(process, pid) catch {
      error => {
        remove_signal_child(pid)
        raise error
      }
    } noraise {
      ready => if ready { Some(pid) } else { None }
    }
  } else {
    None
  }
  Managed(process~, pid~, process_group~)
}

///|
#cfg(any(target="wasm", platform="windows"))
async fn[X] spawn_observed_process(
  group : @async.TaskGroup[X],
  program : String,
  arguments : ArrayView[String],
  _group_process : Bool,
  environment : Map[String, String],
  inherit_environment : Bool,
  stdin : &@process.ProcessInput,
  stdout : &@process.ProcessOutput,
  stderr : &@process.ProcessOutput,
  cwd : String,
) -> ObservedProcess {
  Managed(
    @process.spawn(
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
    ),
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async fn ObservedProcess::wait(self : ObservedProcess) -> Int {
  let Managed(process~, pid~, process_group~) = self
  defer remove_signal_child(pid)
  let status = try process.wait() catch {
    error => {
      match process_group {
        Some(group) => cleanup_process_group_protected(group)
        None => ()
      }
      let signal = caught_signal()
      if @async.is_cancellation_error(error) && signal is Some(number) {
        return -(256 + number)
      }
      raise error
    }
  } noraise {
    value => value
  }
  match process_group {
    Some(group) => cleanup_process_group_protected(group)
    None => ()
  }
  let result = signal_process_status(status)
  result
}

///|
#cfg(any(target="wasm", platform="windows"))
async fn ObservedProcess::wait(self : ObservedProcess) -> Int {
  let Managed(process) = self
  process.wait()
}

///|
#cfg(all(target="native", not(platform="windows")))
fn ObservedProcess::cancel(self : ObservedProcess) -> Unit {
  let Managed(process~, ..) = self
  process.cancel()
}

///|
#cfg(any(target="wasm", platform="windows"))
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
async fn resolve_process_program(program : String, cwd : String) -> String {
  if !windows_process_runtime() {
    return program
  }
  let program = windows_native_program(program, cwd)
  let path = @env.get_env_var("PATH").unwrap_or("")
  let pathext = @env.get_env_var("PATHEXT").unwrap_or(".COM;.EXE;.BAT;.CMD")
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
#cfg(not(target="wasm"))
fn observable_process_command(
  program : String,
  arguments : ArrayView[String],
) -> (String, Array[String], Bool) {
  (program, arguments.to_owned(), false)
}

///|
#cfg(target="wasm")
fn observable_process_command(
  program : String,
  arguments : ArrayView[String],
) -> (String, Array[String], Bool) {
  let shell = program == "sh" ||
    program == "bash" ||
    program == "dash" ||
    program == "zsh" ||
    program == "ksh" ||
    program == "fish" ||
    program.has_suffix("/sh") ||
    program.has_suffix("/bash") ||
    program.has_suffix("/dash") ||
    program.has_suffix("/zsh") ||
    program.has_suffix("/ksh") ||
    program.has_suffix("/fish")
  let temporary_script = program.contains("/just") && program.contains("/")
  if !shell && !temporary_script {
    return (program, arguments.to_owned(), false)
  }
  let wrapped_arguments = [
    "-c", "{ \"$@\" 0<&4 2>&3 3>&- 4<&- & child=$!; wait \"$child\"; status=$?; exit \"$status\"; } 3>&2 4<&0 2>/dev/null",
    "moonjust-signal-wrapper", program,
  ]
  for argument in arguments {
    wrapped_arguments.push(argument)
  }
  ("/bin/sh", wrapped_arguments, true)
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
  status : Int,
  stdout : Bytes,
  stderr : Bytes,
  signal_observable : Bool,
) -> @host.ProcessResult {
  let captured_stdout = if command.stdout() == Capture { stdout } else { b"" }
  let captured_stderr = if command.stderr() == Capture { stderr } else { b"" }
  if status <= -257 {
    @host.ProcessResult::from_interruption(
      signal_from_number(-status - 256),
      captured_stdout,
      captured_stderr,
    )
  } else if status < 0 {
    @host.ProcessResult::from_signal(
      signal_from_status(status),
      captured_stdout,
      captured_stderr,
    )
  } else if signal_observable && status == 143 {
    @host.ProcessResult::from_signal(
      Terminate,
      captured_stdout,
      captured_stderr,
    )
  } else {
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
    resolve_process_program(command.program(), cwd)
  catch {
    error => raise InvalidInput(error.to_string())
  } noraise {
    value => value
  }
  let collected = try
    @async.with_task_group() <| group => {
      let (wrapped_program, wrapped_arguments, temporary_script) = materialize_windows_command(
        resolved_program,
        command.arguments(),
        cwd,
        command.environment(),
        command.inherits_environment(),
      )
      match temporary_script {
        Some(path) => group.add_defer(() => remove_windows_command_script(path))
        None => ()
      }
      let (program, arguments, signal_observable) = observable_process_command(
        wrapped_program, wrapped_arguments,
      )
      let (stdout_reader, stdout_target) = @process.read_from_process()
      let (stderr_reader, stderr_target) = @process.read_from_process()
      let stdout_regular = if command.stdout() == Inherit {
        stdio_kind(@stdio.stdout.fd()) == 1
      } else {
        false
      }
      let stderr_regular = if command.stderr() == Inherit {
        stdio_kind(@stdio.stderr.fd()) == 1
      } else {
        false
      }
      let pipe_stdout = command.stdout() != Inherit || stdout_regular
      let pipe_stderr = command.stderr() != Inherit || stderr_regular
      let merge_regular = stdout_regular &&
        stderr_regular &&
        @stdio.stdout.fd() == @stdio.stderr.fd()
      let group_process = process_group_requested(command.inherits_stdin())
      let child_stdin = if command.inherits_stdin() {
        None
      } else {
        let (child_stdin, writer) = @process.write_to_process()
        group.spawn_bg(() => {
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
      let child_stdout = if pipe_stdout { stdout_target } else { @stdio.stdout }
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
          group,
          program,
          arguments,
          group_process,
          environment,
          command.inherits_environment(),
          @stdio.stdin,
          child_stdout,
          child_stderr,
          cwd,
        )
      } else {
        spawn_observed_process(
          group,
          program,
          arguments,
          group_process,
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
        group.spawn(() => (b"", false))
      } else {
        group.spawn(() => {
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
        })
      }
      let stderr_task = if merge_regular || !pipe_stderr {
        stderr_reader.close()
        group.spawn(() => (b"", false))
      } else {
        group.spawn(() => {
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
        })
      }
      let status = try process.wait() catch {
        _ => {
          process.cancel()
          None
        }
      } noraise {
        value => Some(value)
      }
      let (stdout, stdout_limited) = stdout_task.wait()
      let (stderr, stderr_limited) = stderr_task.wait()
      (
        status, stdout, stderr, stdout_limited, stderr_limited, signal_observable,
      )
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
  let (status, stdout, stderr, stdout_limited, stderr_limited, signal_observable
  ) = collected
  if stdout_limited || stderr_limited {
    raise InvalidInput(
      "process captured output exceeded the \{output_limit}-byte per-stream limit",
    )
  }
  guard status is Some(status) else {
    raise InvalidInput("process execution failed")
  }
  process_result(command, status, stdout, stderr, signal_observable)
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
