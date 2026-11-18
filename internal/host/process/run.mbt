///|
async fn run_process_with_output_limit(
  command : @host.CommandSpec,
  output_limit : Int32,
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
  let mut outcome = Cancelled
  let mut stdout = b""
  let mut stderr = b""
  let mut stdout_limited = false
  let mut stderr_limited = false
  try
    @async.with_task_group() <| group => {
      let (program, arguments, temporary) = materialize_windows_command(
        resolved_program,
        command.arguments(),
        cwd,
        command.environment(),
        command.inherits_environment(),
      )
      if temporary is Some(path) {
        group.add_defer(() => {
          @async.protect_from_cancel(() => remove_windows_command_script(path))
        })
      }
      let input = if command.inherits_stdin() {
        @async_process.ProcessInput::Inherit
      } else if command.stdin().is_empty() {
        Empty
      } else {
        FeedFromParent
      }
      let stdout_mode = match command.stdout() {
        Inherit => @async_process.ProcessOutput::Inherit
        Capture => Collect
        Discard => Discard
      }
      let stderr_mode = match command.stderr() {
        Inherit => @async_process.ProcessOutput::Inherit
        Capture => Collect
        Discard => Discard
      }
      let child = @async_process.spawn(
        group,
        program,
        arguments,
        extra_env=environment_map(command),
        inherit_env=command.inherits_environment(),
        stdin=input,
        stdout=stdout_mode,
        stderr=stderr_mode,
        cwd~,
        cancel_handler=@async_process.graceful_cancel(timeout=5000),
        no_wait=true,
      )
      if input is FeedFromParent {
        group.spawn_bg(() => {
          defer child.stdin.close()
          child.stdin.write(command.stdin()) catch {
            _ => ()
          }
        })
      }
      if stdout_mode is Collect {
        group.spawn_bg(() => {
          let (bytes, limited) = read_bounded_process_output(
            child.stdout,
            output_limit,
            child,
          )
          stdout = bytes
          stdout_limited = limited
        })
      }
      if stderr_mode is Collect {
        group.spawn_bg(() => {
          let (bytes, limited) = read_bounded_process_output(
            child.stderr,
            output_limit,
            child,
          )
          stderr = bytes
          stderr_limited = limited
        })
      }
      outcome = wait_for_child(child)
    }
  catch {
    @host.HostError::InvalidInput(message) => raise InvalidInput(message)
    @host.HostError::PermissionDenied(capability, detail~) =>
      raise PermissionDenied(capability, detail~)
    error => {
      let detail = error.to_string()
      let windows = windows_process_runtime()
      if detail.contains("Permission denied") {
        raise PermissionDenied(
          Process,
          detail="Permission denied (os error 13)",
        )
      }
      if windows && detail.contains("system cannot find the file specified") {
        raise InvalidInput("program not found")
      }
      if windows && detail.contains("directory name is invalid") {
        raise InvalidInput("The directory name is invalid. (os error 267)")
      }
      if detail.contains("No such file or directory") {
        raise InvalidInput("No such file or directory (os error 2)")
      }
      raise InvalidInput(detail)
    }
  }
  if stdout_limited || stderr_limited {
    raise InvalidInput(
      "process captured output exceeded the \{output_limit}-byte per-stream limit",
    )
  }
  process_result(command, outcome, stdout, stderr)
}

///|
pub impl @host.HostProcess for ProcessAdapter with fn run_process(
  _self : ProcessAdapter,
  command : @host.CommandSpec,
) -> @host.ProcessResult raise @host.HostError {
  run_process_with_output_limit(command, MAX_CAPTURED_STREAM_BYTES)
}
