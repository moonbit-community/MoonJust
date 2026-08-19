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
pub fn ProcessAdapter::new() -> ProcessAdapter {
  { output_mutex: Mutex() }
}

///|
#cfg(all(target="native", not(platform="windows")))
priv enum ObservedProcess {
  Managed(process~ : @process.Process, pid~ : Int)
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
  Managed(process~, pid~)
}

///|
#cfg(any(target="wasm", platform="windows"))
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
  let Managed(process~, pid~) = self
  let status = try process.wait() catch {
    error => {
      remove_signal_child(pid)
      raise error
    }
  } noraise {
    value => value
  }
  let result = signal_process_status(status)
  remove_signal_child(pid)
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
  if !program.contains("/") && !program.contains("\\") {
    for raw_directory in path.split(";") {
      let directory = raw_directory.trim(chars="\"")
      bases.push(
        if directory.is_empty() {
          program
        } else if directory.has_suffix("/") || directory.has_suffix("\\") {
          directory.to_owned() + program
        } else {
          directory.to_owned() + "\\" + program
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
      let suffix = if extension.has_prefix(".") {
        extension.to_owned()
      } else {
        "." + extension.to_owned()
      }
      candidates.push(base + suffix)
    }
  }
  candidates
}

///|
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
async fn resolve_process_program(program : String) -> String {
  if !windows_process_runtime() {
    return program
  }
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
        let written = write_stdio(output_mutex, stream, chunk)
        if written != chunk.length() {
          process.cancel()
          raise @host.HostError::InvalidInput(
            "incomplete inherited output write",
          )
        }
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
  let resolved_program = try resolve_process_program(command.program()) catch {
    error => raise InvalidInput(error.to_string())
  } noraise {
    value => value
  }
  let (batch_program, batch_arguments) = windows_batch_command(
    resolved_program,
    command.arguments(),
    windows_process_runtime(),
  )
  let (program, arguments, signal_observable) = observable_process_command(
    batch_program, batch_arguments,
  )
  let collected = try
    @async.with_task_group() <| group => {
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
      let process = if command.inherits_stdin() {
        match (pipe_stdout, pipe_stderr) {
          (false, false) =>
            spawn_observed_process(
              group,
              program,
              arguments,
              environment_map(command),
              command.inherits_environment(),
              @stdio.stdin,
              @stdio.stdout,
              @stdio.stderr,
              cwd,
            )
          (false, true) =>
            spawn_observed_process(
              group,
              program,
              arguments,
              environment_map(command),
              command.inherits_environment(),
              @stdio.stdin,
              @stdio.stdout,
              stderr_target,
              cwd,
            )
          (true, false) =>
            spawn_observed_process(
              group,
              program,
              arguments,
              environment_map(command),
              command.inherits_environment(),
              @stdio.stdin,
              stdout_target,
              @stdio.stderr,
              cwd,
            )
          (true, true) =>
            spawn_observed_process(
              group,
              program,
              arguments,
              environment_map(command),
              command.inherits_environment(),
              @stdio.stdin,
              stdout_target,
              if merge_regular {
                stdout_target
              } else {
                stderr_target
              },
              cwd,
            )
        }
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
        match (pipe_stdout, pipe_stderr) {
          (false, false) =>
            spawn_observed_process(
              group,
              program,
              arguments,
              environment_map(command),
              command.inherits_environment(),
              child_stdin,
              @stdio.stdout,
              @stdio.stderr,
              cwd,
            )
          (false, true) =>
            spawn_observed_process(
              group,
              program,
              arguments,
              environment_map(command),
              command.inherits_environment(),
              child_stdin,
              @stdio.stdout,
              stderr_target,
              cwd,
            )
          (true, false) =>
            spawn_observed_process(
              group,
              program,
              arguments,
              environment_map(command),
              command.inherits_environment(),
              child_stdin,
              stdout_target,
              @stdio.stderr,
              cwd,
            )
          (true, true) =>
            spawn_observed_process(
              group,
              program,
              arguments,
              environment_map(command),
              command.inherits_environment(),
              child_stdin,
              stdout_target,
              if merge_regular {
                stdout_target
              } else {
                stderr_target
              },
              cwd,
            )
        }
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
      (status, stdout, stderr, stdout_limited, stderr_limited)
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
  let (status, stdout, stderr, stdout_limited, stderr_limited) = collected
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
