///|
fn live_spec(spec : @host.CommandSpec) -> @host.CommandSpec {
  let spec = spec.copy()
  spec.set_inherit_stdin(true)
  if spec.stdout() == Capture {
    spec.set_stdout(Inherit)
  }
  if spec.stderr() == Capture {
    spec.set_stderr(Inherit)
  }
  spec
}

///|
async fn[O : @host.HostAsyncOutput] emit_live(
  output : O,
  stream : @host.OutputStream,
  bytes : BytesView,
  commands : Int,
) -> Int raise LiveRuntimeError {
  if bytes.is_empty() {
    return 0
  }
  let written = try
    @async.with_task_group() <| group => {
      let write = group.spawn(() => {
        @host.HostAsyncOutput::write_output(output, stream, bytes.to_owned())
      })
      write.wait() catch {
        _ =>
          raise @host.HostError::InvalidInput("failed to write runtime output")
      }
    }
  catch {
    _ =>
      raise live_failure(
        @planner.ExecutionError::host(
          InvalidInput("failed to write runtime output"),
        ),
        commands,
      )
  } noraise {
    value => value
  }
  if written != bytes.length() {
    raise live_failure(
      @planner.ExecutionError::host(
        InvalidInput("incomplete runtime output write"),
      ),
      commands,
    )
  }
  written
}

///|
async fn[
  P : @host.HostAsyncProcess,
  O : @host.HostAsyncOutput,
  S : @host.HostAsyncScriptTemp,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] execute_live_steps(
  process : P,
  output : O,
  scripts : S,
  effects : H,
  steps : ArrayView[@planner.PlannedStep],
  options : @planner.ExecutionOptions,
  initial_stderr : BytesView,
) -> ExecutionSummary raise LiveRuntimeError {
  let mut commands = 0
  ignore(emit_live(output, Stderr, initial_stderr, commands))
  let mut guard_failed = false
  for step in steps {
    if guard_failed {
      continue
    }
    let started = if options.time() { Some(@async.now()) } else { None }
    let (recipe, line, ignore_error, is_guard, continue_signals, result) = match
      step {
      Command(command, echo) => {
        ignore(emit_live(output, Stderr, echo, commands))
        let result = @host.HostAsyncProcess::run_process_async(
          process,
          live_spec(command.spec()),
        ) catch {
          error =>
            raise live_failure(
              shell_launch_error(
                command.recipe(),
                command.spec().program(),
                error,
              ),
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
        ignore(emit_live(output, Stderr, echo, commands))
        if initial_stderr.is_empty() && script.contents().is_empty() {
          continue
        }
        let result = try
          @async.with_task_group() <| group => {
            let materialized = @planner.materialize_script_async(
              scripts, script,
            ) catch {
              error => raise live_failure(error, commands)
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
              live_spec(materialized.spec()),
            ) catch {
              error =>
                raise live_failure(
                  @planner.ExecutionError::host(error),
                  commands,
                )
            }
          }
        catch {
          LiveExecution(..) as failure => raise failure
          _ =>
            raise live_failure(
              @planner.ExecutionError::host(InvalidInput("script task failed")),
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
          error => raise live_failure(error, commands)
        }
        ignore(emit_live(output, Stderr, echo, commands))
        let result = @host.HostAsyncProcess::run_process_async(
          process,
          live_spec(command.spec()),
        ) catch {
          error =>
            raise live_failure(
              shell_launch_error(
                command.recipe(),
                command.spec().program(),
                error,
              ),
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
    // Fake hosts and effect adapters may still return captured bytes. Forward
    // them here; real live processes use inherited streams and return empty.
    ignore(emit_live(output, Stdout, result.stdout(), commands))
    ignore(emit_live(output, Stderr, result.stderr(), commands))
    match started {
      Some(value) =>
        ignore(
          emit_live(
            output,
            Stderr,
            @planner.render_elapsed_message(recipe, @async.now() - value)[:],
            commands,
          ),
        )
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
          raise live_failure(GuardCode(recipe~, line~, code~), commands)
        Signaled(signal) =>
          raise live_failure(
            GuardCode(recipe~, line~, code=signal.exit_code()),
            commands,
          )
        Interrupted(signal) =>
          raise live_failure(Interrupted(signal~), commands)
      }
    } else {
      match result.termination() {
        Exited(0) => ()
        Exited(_) if ignore_error => ()
        Exited(exit_code) =>
          raise live_failure(
            @planner.ExecutionError::command_failed(recipe, line, exit_code),
            commands,
          )
        Signaled(_) if ignore_error => ()
        Signaled(signal) =>
          raise live_failure(
            @planner.ExecutionError::command_signaled(recipe, line, signal),
            commands,
          )
        Interrupted(_) if ignore_error => ()
        Interrupted(signal) =>
          raise live_failure(Interrupted(signal~), commands)
      }
    }
  }
  { commands, }
}

///|
