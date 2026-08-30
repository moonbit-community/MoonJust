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
