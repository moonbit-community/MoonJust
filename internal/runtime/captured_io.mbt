///|
async fn[
  P : @host.HostAsyncProcess,
  S : @host.HostAsyncScriptTemp,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] execute_steps(
  process : P,
  scripts : S,
  effects : H,
  steps : ArrayView[@planner.PlannedStep],
  options : @planner.ExecutionOptions,
  initial_stderr : BytesView,
) -> @planner.ExecutionReport raise RuntimeError {
  let stdout : Array[Byte] = []
  let stderr : Array[Byte] = []
  for byte in initial_stderr {
    stderr.push(byte)
  }
  let mut commands = 0
  let mut guard_failed = false
  for step in steps {
    if guard_failed {
      continue
    }
    let started = if options.time() { Some(@async.now()) } else { None }
    let (recipe, line, ignore_error, is_guard, continue_signals, result) = match
      step {
      Command(command, echo) => {
        for byte in echo {
          stderr.push(byte)
        }
        let result = @host.HostAsyncProcess::run_process_async(
          process,
          command.spec(),
        ) catch {
          error =>
            raise runtime_failure(
              shell_launch_error(
                command.recipe(),
                command.spec().program(),
                error,
              ),
              stdout,
              stderr,
              commands,
            )
        }
        (
          command.recipe(),
          command.line(),
          command.ignore_error(),
          false,
          command.continue_signals(),
          result,
        )
      }
      Script(script, echo) => {
        for byte in echo {
          stderr.push(byte)
        }
        if initial_stderr.is_empty() && script.contents().is_empty() {
          continue
        }
        let result = try
          @async.with_task_group() <| group => {
            let materialized = @planner.materialize_script_async(
              scripts, script,
            ) catch {
              error => raise runtime_failure(error, stdout, stderr, commands)
            }
            group.add_defer(() => {
              try
                @async.protect_from_cancel(() => {
                  @planner.cleanup_materialized_script_async(
                    scripts, materialized,
                  )
                })
              catch {
                _ => ()
              } noraise {
                _ => ()
              }
            })
            @host.HostAsyncProcess::run_process_async(
              process,
              materialized.spec(),
            ) catch {
              error =>
                raise runtime_failure(
                  @planner.ExecutionError::host(error),
                  stdout,
                  stderr,
                  commands,
                )
            }
          }
        catch {
          Execution(..) as failure => raise failure
          _ =>
            raise runtime_failure(
              @planner.ExecutionError::host(InvalidInput("script task failed")),
              stdout,
              stderr,
              commands,
            )
        } noraise {
          value => value
        }
        (script.recipe(), 0, false, false, script.continue_signals(), result)
      }
      Line(line) => {
        let (command, echo) = @planner.materialize_line_async(
          process, effects, line,
        ) catch {
          error => raise runtime_failure(error, stdout, stderr, commands)
        }
        for byte in echo {
          stderr.push(byte)
        }
        let result = @host.HostAsyncProcess::run_process_async(
          process,
          command.spec(),
        ) catch {
          error =>
            raise runtime_failure(
              shell_launch_error(
                command.recipe(),
                command.spec().program(),
                error,
              ),
              stdout,
              stderr,
              commands,
            )
        }
        (
          command.recipe(),
          command.line(),
          command.ignore_error(),
          command.is_guard(),
          command.continue_signals(),
          result,
        )
      }
    }
    commands += 1
    for byte in result.stdout() {
      stdout.push(byte)
    }
    for byte in result.stderr() {
      stderr.push(byte)
    }
    match started {
      Some(value) =>
        for
          byte in @planner.render_elapsed_message(recipe, @async.now() - value) {
          stderr.push(byte)
        }
      None => ()
    }
    let continued = match result.termination() {
      Signaled(signal) | Interrupted(signal) =>
        continue_signals.contains(signal)
      Exited(_) => false
    }
    if continued {
      ()
    } else if is_guard {
      match result.termination() {
        Exited(0) => ()
        Exited(1) => guard_failed = true
        Exited(code) =>
          raise runtime_failure(
            GuardCode(recipe~, line~, code~),
            stdout,
            stderr,
            commands,
          )
        Signaled(signal) =>
          raise runtime_failure(
            GuardCode(recipe~, line~, code=signal.exit_code()),
            stdout,
            stderr,
            commands,
          )
        Interrupted(signal) =>
          raise runtime_failure(Interrupted(signal~), stdout, stderr, commands)
      }
    } else {
      match result.termination() {
        Exited(0) => ()
        Exited(_) if ignore_error => ()
        Exited(exit_code) =>
          raise runtime_failure(
            @planner.ExecutionError::command_failed(recipe, line, exit_code),
            stdout,
            stderr,
            commands,
          )
        Signaled(_) if ignore_error => ()
        Signaled(signal) =>
          raise runtime_failure(
            @planner.ExecutionError::command_signaled(recipe, line, signal),
            stdout,
            stderr,
            commands,
          )
        Interrupted(_) if ignore_error => ()
        Interrupted(signal) =>
          raise runtime_failure(Interrupted(signal~), stdout, stderr, commands)
      }
    }
  }
  @planner.ExecutionReport::new(
    Bytes::from_array(stdout),
    Bytes::from_array(stderr),
    commands,
  )
}

///|
fn append_report(
  stdout : Array[Byte],
  stderr : Array[Byte],
  report : @planner.ExecutionReport,
) -> Int {
  for byte in report.stdout() {
    stdout.push(byte)
  }
  for byte in report.stderr() {
    stderr.push(byte)
  }
  report.commands()
}

///|
