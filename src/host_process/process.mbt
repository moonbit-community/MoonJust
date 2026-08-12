///|
/// Native/wasm1 process leaf backed by `moonbitlang/async/process`.
pub struct ProcessAdapter {
  marker : Unit
}

///|
/// Captured output is retained so the runtime can flush parallel tasks in
/// deterministic invocation order. Bound each stream to keep one child from
/// exhausting the executor while its pipe is drained with backpressure.
const MAX_CAPTURED_STREAM_BYTES : Int = 16 * 1024 * 1024

///|
pub fn ProcessAdapter::new() -> ProcessAdapter {
  { marker: () }
}

///|
fn signal_from_status(status : Int) -> @host.SignalKind {
  match -status {
    1 => Hangup
    2 => Interrupt
    15 => Terminate
    value => OtherSignal(value)
  }
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
async fn read_bounded_process_output(
  reader : @process.ReadFromProcess,
  limit : Int,
  retain : Bool,
  process : @process.Process,
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
) -> @host.ProcessResult {
  let captured_stdout = if command.stdout() == Capture { stdout } else { b"" }
  let captured_stderr = if command.stderr() == Capture { stderr } else { b"" }
  if status < 0 {
    @host.ProcessResult::from_signal(
      signal_from_status(status),
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
) -> @host.ProcessResult raise @host.HostError {
  if output_limit < 0 {
    raise InvalidInput("captured process output limit must be non-negative")
  }
  let cwd = command.cwd().map(fn(path) { path.as_string() }).unwrap_or(".")
  let collected = try
    @async.with_task_group() <| group => {
      let (stdout_reader, stdout_target) = @process.read_from_process()
      let (stderr_reader, stderr_target) = @process.read_from_process()
      let process = if command.inherits_stdin() {
        match (command.stdout(), command.stderr()) {
          (Inherit, Inherit) =>
            @process.spawn(
              group,
              command.program(),
              command.arguments(),
              extra_env=environment_map(command),
              inherit_env=command.inherits_environment(),
              stdin=@stdio.stdin,
              stdout=@stdio.stdout,
              stderr=@stdio.stderr,
              cwd~,
              cancel_handler=@process.graceful_cancel(timeout=5000),
              no_wait=true,
            )
          (Inherit, _) =>
            @process.spawn(
              group,
              command.program(),
              command.arguments(),
              extra_env=environment_map(command),
              inherit_env=command.inherits_environment(),
              stdin=@stdio.stdin,
              stdout=@stdio.stdout,
              stderr=stderr_target,
              cwd~,
              cancel_handler=@process.graceful_cancel(timeout=5000),
              no_wait=true,
            )
          (_, Inherit) =>
            @process.spawn(
              group,
              command.program(),
              command.arguments(),
              extra_env=environment_map(command),
              inherit_env=command.inherits_environment(),
              stdin=@stdio.stdin,
              stdout=stdout_target,
              stderr=@stdio.stderr,
              cwd~,
              cancel_handler=@process.graceful_cancel(timeout=5000),
              no_wait=true,
            )
          _ =>
            @process.spawn(
              group,
              command.program(),
              command.arguments(),
              extra_env=environment_map(command),
              inherit_env=command.inherits_environment(),
              stdin=@stdio.stdin,
              stdout=stdout_target,
              stderr=stderr_target,
              cwd~,
              cancel_handler=@process.graceful_cancel(timeout=5000),
              no_wait=true,
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
        match (command.stdout(), command.stderr()) {
          (Inherit, Inherit) =>
            @process.spawn(
              group,
              command.program(),
              command.arguments(),
              extra_env=environment_map(command),
              inherit_env=command.inherits_environment(),
              stdin=child_stdin,
              stdout=@stdio.stdout,
              stderr=@stdio.stderr,
              cwd~,
              cancel_handler=@process.graceful_cancel(timeout=5000),
              no_wait=true,
            )
          (Inherit, _) =>
            @process.spawn(
              group,
              command.program(),
              command.arguments(),
              extra_env=environment_map(command),
              inherit_env=command.inherits_environment(),
              stdin=child_stdin,
              stdout=@stdio.stdout,
              stderr=stderr_target,
              cwd~,
              cancel_handler=@process.graceful_cancel(timeout=5000),
              no_wait=true,
            )
          (_, Inherit) =>
            @process.spawn(
              group,
              command.program(),
              command.arguments(),
              extra_env=environment_map(command),
              inherit_env=command.inherits_environment(),
              stdin=child_stdin,
              stdout=stdout_target,
              stderr=@stdio.stderr,
              cwd~,
              cancel_handler=@process.graceful_cancel(timeout=5000),
              no_wait=true,
            )
          _ =>
            @process.spawn(
              group,
              command.program(),
              command.arguments(),
              extra_env=environment_map(command),
              inherit_env=command.inherits_environment(),
              stdin=child_stdin,
              stdout=stdout_target,
              stderr=stderr_target,
              cwd~,
              cancel_handler=@process.graceful_cancel(timeout=5000),
              no_wait=true,
            )
        }
      }
      let stdout_task = if command.stdout() == Inherit {
        stdout_reader.close()
        group.spawn(() => (b"", false))
      } else {
        group.spawn(() => {
          read_bounded_process_output(
            stdout_reader,
            output_limit,
            command.stdout() == Capture,
            process,
          )
        })
      }
      let stderr_task = if command.stderr() == Inherit {
        stderr_reader.close()
        group.spawn(() => (b"", false))
      } else {
        group.spawn(() => {
          read_bounded_process_output(
            stderr_reader,
            output_limit,
            command.stderr() == Capture,
            process,
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
    _ => raise InvalidInput("process execution failed")
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
  process_result(command, status, stdout, stderr)
}

///|
pub impl @host.HostAsyncProcess for ProcessAdapter with fn run_process_async(
  _self : ProcessAdapter,
  command : @host.CommandSpec,
) -> @host.ProcessResult raise @host.HostError {
  run_process_with_output_limit(command, MAX_CAPTURED_STREAM_BYTES)
}
