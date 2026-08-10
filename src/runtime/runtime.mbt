///|
/// A process failure retains all output emitted by completed steps so the CLI
/// can report the same command echoes and child streams before the diagnostic.
pub(all) suberror RuntimeError {
  Execution(
    error~ : @executor.ExecutionError,
    stdout~ : Bytes,
    stderr~ : Bytes,
    commands~ : Int
  )
} derive(Debug)

///|
fn runtime_failure(
  error : @executor.ExecutionError,
  stdout : Array[Byte],
  stderr : Array[Byte],
  commands : Int,
) -> RuntimeError {
  Execution(
    error~,
    stdout=Bytes::from_array(stdout.copy()),
    stderr=Bytes::from_array(stderr.copy()),
    commands~,
  )
}

///|
pub fn RuntimeError::error(self : RuntimeError) -> @executor.ExecutionError {
  match self {
    Execution(error~, ..) => error
  }
}

///|
pub fn RuntimeError::stdout(self : RuntimeError) -> BytesView {
  match self {
    Execution(stdout~, ..) => stdout[:]
  }
}

///|
pub fn RuntimeError::stderr(self : RuntimeError) -> BytesView {
  match self {
    Execution(stderr~, ..) => stderr[:]
  }
}

///|
pub fn RuntimeError::commands(self : RuntimeError) -> Int {
  match self {
    Execution(commands~, ..) => commands
  }
}

///|
pub fn RuntimeError::message(self : RuntimeError) -> String {
  self.error().message()
}

///|
pub fn RuntimeError::exit_code(self : RuntimeError) -> Int {
  self.error().exit_code()
}

///|
/// Execute a prevalidated plan sequentially. Structured task cancellation is
/// delegated to the process adapter, which must terminate and reap its child.
pub async fn[
  P : @host.HostAsyncProcess,
  S : @host.HostAsyncScriptTemp,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] execute_plan(
  process : P,
  scripts : S,
  effects : H,
  plan : @executor.ExecutionPlan,
) -> @executor.ExecutionReport raise RuntimeError {
  let stdout : Array[Byte] = []
  let stderr : Array[Byte] = []
  for byte in plan.stderr() {
    stderr.push(byte)
  }
  let mut commands = 0
  for step in plan.steps() {
    let started = if plan.options().time() { Some(@async.now()) } else { None }
    let (recipe, line, ignore_error, result) = match step {
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
              @executor.ExecutionError::host(error),
              stdout,
              stderr,
              commands,
            )
        }
        (command.recipe(), command.line(), command.ignore_error(), result)
      }
      Script(script, echo) => {
        for byte in echo {
          stderr.push(byte)
        }
        if plan.stderr().is_empty() && script.contents().is_empty() {
          continue
        }
        let result = try
          @async.with_task_group() <| group => {
            let materialized = @executor.materialize_script_async(
              scripts, script,
            ) catch {
              error => raise runtime_failure(error, stdout, stderr, commands)
            }
            group.add_defer(() => {
              try
                @async.protect_from_cancel(
                  () => {
                    @executor.cleanup_materialized_script_async(
                      scripts, materialized,
                    )
                  },
                  resume_on_cancel=false,
                )
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
                  @executor.ExecutionError::host(error),
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
              @executor.ExecutionError::host(InvalidInput("script task failed")),
              stdout,
              stderr,
              commands,
            )
        } noraise {
          value => value
        }
        (script.recipe(), 0, false, result)
      }
      Line(line) => {
        let (command, echo) = @executor.materialize_line_async(
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
              @executor.ExecutionError::host(error),
              stdout,
              stderr,
              commands,
            )
        }
        (command.recipe(), command.line(), command.ignore_error(), result)
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
          byte in @executor.render_elapsed_message(recipe, @async.now() - value) {
          stderr.push(byte)
        }
      None => ()
    }
    match result.termination() {
      Exited(0) => ()
      Exited(_) if ignore_error => ()
      Exited(exit_code) =>
        raise runtime_failure(
          @executor.ExecutionError::command_failed(recipe, line, exit_code),
          stdout,
          stderr,
          commands,
        )
      Signaled(_) if ignore_error => ()
      Signaled(signal) =>
        raise runtime_failure(
          @executor.ExecutionError::command_signaled(recipe, line, signal),
          stdout,
          stderr,
          commands,
        )
    }
  }
  @executor.ExecutionReport::new(
    Bytes::from_array(stdout),
    Bytes::from_array(stderr),
    commands,
  )
}
