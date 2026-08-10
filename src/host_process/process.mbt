///|
/// Native/wasm1 process leaf backed by `moonbitlang/async/process`.
pub struct ProcessAdapter {
  marker : Unit
}

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
async fn publish_inherited(
  command : @host.CommandSpec,
  stdout : Bytes,
  stderr : Bytes,
) -> Unit raise @host.HostError {
  if command.stdout() == Inherit && !stdout.is_empty() {
    @stdio.stdout.write(stdout) catch {
      _ => raise InvalidInput("failed to write inherited process stdout")
    }
  }
  if command.stderr() == Inherit && !stderr.is_empty() {
    @stdio.stderr.write(stderr) catch {
      _ => raise InvalidInput("failed to write inherited process stderr")
    }
  }
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
async fn run_inheriting_stdin(
  command : @host.CommandSpec,
) -> @host.ProcessResult raise @host.HostError {
  let cwd = command.cwd().map(fn(path) { path.as_string() }).unwrap_or(".")
  let (status, stdout, stderr) = @process.collect_output(
    command.program(),
    command.arguments(),
    extra_env=environment_map(command),
    inherit_env=command.inherits_environment(),
    stdin=@stdio.stdin,
    cwd~,
  ) catch {
    _ => raise InvalidInput("process execution failed")
  }
  let stdout = stdout.binary()
  let stderr = stderr.binary()
  publish_inherited(command, stdout, stderr)
  process_result(command, status, stdout, stderr)
}

///|
async fn run_buffered_stdin(
  command : @host.CommandSpec,
) -> @host.ProcessResult raise @host.HostError {
  let cwd = command.cwd().map(fn(path) { path.as_string() }).unwrap_or(".")
  try
    @async.with_task_group() <| group => {
      let (child_stdin, writer) = @process.write_to_process()
      group.spawn_bg(() => {
        defer writer.close()
        if !command.stdin().is_empty() {
          writer.write(command.stdin()) catch {
            _ => ()
          }
        }
      })
      let (status, stdout, stderr) = @process.collect_output(
        command.program(),
        command.arguments(),
        extra_env=environment_map(command),
        inherit_env=command.inherits_environment(),
        stdin=child_stdin,
        cwd~,
      )
      let stdout = stdout.binary()
      let stderr = stderr.binary()
      publish_inherited(command, stdout, stderr)
      process_result(command, status, stdout, stderr)
    }
  catch {
    _ => raise InvalidInput("process execution failed")
  } noraise {
    result => result
  }
}

///|
pub impl @host.HostAsyncProcess for ProcessAdapter with fn run_process_async(
  _self : ProcessAdapter,
  command : @host.CommandSpec,
) -> @host.ProcessResult raise @host.HostError {
  if command.inherits_stdin() {
    run_inheriting_stdin(command)
  } else {
    run_buffered_stdin(command)
  }
}
