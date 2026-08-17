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
/// A process failure for live execution. Child output has already been sent to
/// the configured `HostAsyncOutput` and is therefore intentionally not stored
/// for replay.
pub(all) suberror LiveRuntimeError {
  LiveExecution(
    error~ : @executor.ExecutionError,
    commands~ : Int,
    show_message~ : Bool
  )
} derive(Debug)

///|
pub struct ExecutionSummary {
  commands : Int
} derive(Eq, Debug)

///|
pub fn ExecutionSummary::commands(self : ExecutionSummary) -> Int {
  self.commands
}

///|
fn live_failure(
  error : @executor.ExecutionError,
  commands : Int,
  show_message? : Bool = true,
) -> LiveRuntimeError {
  LiveExecution(error~, commands~, show_message~)
}

///|
pub fn LiveRuntimeError::error(
  self : LiveRuntimeError,
) -> @executor.ExecutionError {
  match self {
    LiveExecution(error~, ..) => error
  }
}

///|
pub fn LiveRuntimeError::commands(self : LiveRuntimeError) -> Int {
  match self {
    LiveExecution(commands~, ..) => commands
  }
}

///|
pub fn LiveRuntimeError::show_message(self : LiveRuntimeError) -> Bool {
  match self {
    LiveExecution(show_message~, ..) => show_message
  }
}

///|
fn LiveRuntimeError::with_recipe_exit_message(
  self : LiveRuntimeError,
  show_message : Bool,
) -> LiveRuntimeError {
  match self.error() {
    CommandFailed(..) | CommandSignaled(..) =>
      live_failure(self.error(), self.commands(), show_message~)
    _ => self
  }
}

///|
pub fn LiveRuntimeError::message(self : LiveRuntimeError) -> String {
  self.error().message()
}

///|
pub fn LiveRuntimeError::exit_code(self : LiveRuntimeError) -> Int {
  self.error().exit_code()
}

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
priv enum TaskOutcome {
  Completed(@executor.ExecutionReport)
  Failed(RuntimeError)
  Blocked
}

///|
priv enum LiveTaskOutcome {
  LiveCompleted(ExecutionSummary)
  LiveFailed(LiveRuntimeError)
  LiveBlocked
}

///|
async fn[
  P : @host.HostAsyncProcess,
  S : @host.HostAsyncScriptTemp,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] execute_steps(
  process : P,
  scripts : S,
  effects : H,
  steps : ArrayView[@executor.PlannedStep],
  options : @executor.ExecutionOptions,
  initial_stderr : BytesView,
) -> @executor.ExecutionReport raise RuntimeError {
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
              ShellNotFound(
                recipe=command.recipe(),
                shell=command.spec().program(),
                detail=Repr(error).to_string(),
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
        (script.recipe(), 0, false, false, script.continue_signals(), result)
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
          byte in @executor.render_elapsed_message(recipe, @async.now() - value) {
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
        Interrupted(_) if ignore_error => ()
        Interrupted(signal) =>
          raise runtime_failure(Interrupted(signal~), stdout, stderr, commands)
      }
    }
  }
  @executor.ExecutionReport::new(
    Bytes::from_array(stdout),
    Bytes::from_array(stderr),
    commands,
  )
}

///|
fn append_report(
  stdout : Array[Byte],
  stderr : Array[Byte],
  report : @executor.ExecutionReport,
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
fn process_error_detail(error : @host.HostError) -> String {
  match error {
    InvalidInput(detail) => detail
    PermissionDenied(_, detail~) => detail
    NotFound(path) => "No such file or directory: " + path.as_string()
    AlreadyExists(path) => "already exists: " + path.as_string()
    CapabilityDenied(capability) =>
      "capability denied: " + Repr(capability).to_string()
    CapabilityUnavailable(capability) =>
      "capability unavailable: " + Repr(capability).to_string()
    UnexpectedProcess(_) | ProcessMismatch(_) => "unexpected process invocation"
    RandomExhausted(_) => "host randomness unavailable"
  }
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
        @executor.ExecutionError::host(
          InvalidInput("failed to write runtime output"),
        ),
        commands,
      )
  } noraise {
    value => value
  }
  if written != bytes.length() {
    raise live_failure(
      @executor.ExecutionError::host(
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
  steps : ArrayView[@executor.PlannedStep],
  options : @executor.ExecutionOptions,
  initial_stderr : BytesView,
) -> ExecutionSummary raise LiveRuntimeError {
  let mut commands = 0
  let initial_written = emit_live(output, Stderr, initial_stderr, commands)
  if initial_written != initial_stderr.length() {
    raise live_failure(
      @executor.ExecutionError::host(
        InvalidInput("incomplete initial runtime output"),
      ),
      commands,
    )
  }
  let mut guard_failed = false
  for step in steps {
    if guard_failed {
      continue
    }
    let started = if options.time() { Some(@async.now()) } else { None }
    let (recipe, line, ignore_error, is_guard, continue_signals, result) = match
      step {
      Command(command, echo) => {
        let echo_written = emit_live(output, Stderr, echo, commands)
        if echo_written != echo.length() {
          raise live_failure(
            @executor.ExecutionError::host(
              InvalidInput("incomplete command echo"),
            ),
            commands,
          )
        }
        let result = @host.HostAsyncProcess::run_process_async(
          process,
          live_spec(command.spec()),
        ) catch {
          error =>
            raise live_failure(
              ShellNotFound(
                recipe=command.recipe(),
                shell=command.spec().program(),
                detail=process_error_detail(error),
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
        let echo_written = emit_live(output, Stderr, echo, commands)
        if echo_written != echo.length() {
          raise live_failure(
            @executor.ExecutionError::host(
              InvalidInput("incomplete script echo"),
            ),
            commands,
          )
        }
        if initial_stderr.is_empty() && script.contents().is_empty() {
          continue
        }
        let result = try
          @async.with_task_group() <| group => {
            let materialized = @executor.materialize_script_async(
              scripts, script,
            ) catch {
              error => raise live_failure(error, commands)
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
              live_spec(materialized.spec()),
            ) catch {
              error =>
                raise live_failure(
                  @executor.ExecutionError::host(error),
                  commands,
                )
            }
          }
        catch {
          LiveExecution(..) as failure => raise failure
          _ =>
            raise live_failure(
              @executor.ExecutionError::host(InvalidInput("script task failed")),
              commands,
            )
        } noraise {
          value => value
        }
        (script.recipe(), 0, false, false, script.continue_signals(), result)
      }
      Line(line) => {
        let (command, echo) = @executor.materialize_line_async(
          process, effects, line,
        ) catch {
          error => raise live_failure(error, commands)
        }
        let echo_written = emit_live(output, Stderr, echo, commands)
        if echo_written != echo.length() {
          raise live_failure(
            @executor.ExecutionError::host(InvalidInput("incomplete line echo")),
            commands,
          )
        }
        let result = @host.HostAsyncProcess::run_process_async(
          process,
          live_spec(command.spec()),
        ) catch {
          error =>
            raise live_failure(
              ShellNotFound(
                recipe=command.recipe(),
                shell=command.spec().program(),
                detail=process_error_detail(error),
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
    let stdout_written = emit_live(output, Stdout, result.stdout(), commands)
    if stdout_written != result.stdout().length() {
      raise live_failure(
        @executor.ExecutionError::host(
          InvalidInput("incomplete stdout forwarding"),
        ),
        commands,
      )
    }
    let stderr_written = emit_live(output, Stderr, result.stderr(), commands)
    if stderr_written != result.stderr().length() {
      raise live_failure(
        @executor.ExecutionError::host(
          InvalidInput("incomplete stderr forwarding"),
        ),
        commands,
      )
    }
    match started {
      Some(value) =>
        ignore(
          emit_live(
            output,
            Stderr,
            @executor.render_elapsed_message(recipe, @async.now() - value)[:],
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
            @executor.ExecutionError::command_failed(recipe, line, exit_code),
            commands,
          )
        Signaled(_) if ignore_error => ()
        Signaled(signal) =>
          raise live_failure(
            @executor.ExecutionError::command_signaled(recipe, line, signal),
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
fn invalid_plan(message : String) -> RuntimeError {
  runtime_failure(
    @executor.ExecutionError::host(InvalidInput(message)),
    [],
    [],
    0,
  )
}

///|
fn cache_failure(message : String) -> RuntimeError {
  runtime_failure(CacheFailure(message~), [], [], 0)
}

///|
fn prepend_report_stderr(
  prefix : BytesView,
  report : @executor.ExecutionReport,
) -> @executor.ExecutionReport {
  let stderr : Array[Byte] = []
  for byte in prefix {
    stderr.push(byte)
  }
  for byte in report.stderr() {
    stderr.push(byte)
  }
  @executor.ExecutionReport::new(
    report.stdout().to_owned(),
    Bytes::from_array(stderr),
    report.commands(),
  )
}

///|
fn append_report_stderr(
  report : @executor.ExecutionReport,
  suffix : BytesView,
) -> @executor.ExecutionReport {
  let stderr = report.stderr().to_array()
  for byte in suffix {
    stderr.push(byte)
  }
  @executor.ExecutionReport::new(
    report.stdout().to_owned(),
    Bytes::from_array(stderr),
    report.commands(),
  )
}

///|
fn failure_after_report(
  error : @executor.ExecutionError,
  report : @executor.ExecutionReport,
) -> RuntimeError {
  Execution(
    error~,
    stdout=report.stdout().to_owned(),
    stderr=report.stderr().to_owned(),
    commands=report.commands(),
  )
}

///|
fn running_message(recipe : String, color_enabled : Bool) -> Bytes {
  let text = "===> running recipe `\{recipe}`..."
  if color_enabled {
    @utf8.encode("\u{001b}[1;36m" + text + "\u{001b}[0m\n")
  } else {
    @utf8.encode(text + "\n")
  }
}

///|
fn cache_path(
  base : @path.PathValue,
  relative : String,
) -> @path.PathValue raise RuntimeError {
  let child = @path.PathValue::new(relative, base.flavor()) catch {
    _ => raise cache_failure("invalid cache path `\{relative}`")
  }
  base.join(child) catch {
    _ => raise cache_failure("cache path flavor mismatch")
  }
}

///|
fn[H : @host.HostFs] cache_key(
  effects : H,
  directive : @executor.CacheDirective,
) -> @cache.CacheKey raise RuntimeError {
  let inputs : Array[@cache.InputDigest] = []
  for relative in directive.inputs() {
    let path = cache_path(directive.working_directory(), relative)
    let exists = @host.HostFs::file_exists(effects, path) catch {
      error =>
        raise runtime_failure(@executor.ExecutionError::host(error), [], [], 0)
    }
    if !exists {
      raise cache_failure("cache input does not exist: `\{path.as_string()}`")
    }
    let metadata = @host.HostFs::metadata(effects, path) catch {
      NotFound(_) =>
        raise cache_failure("cache input does not exist: `\{path.as_string()}`")
      error =>
        raise runtime_failure(@executor.ExecutionError::host(error), [], [], 0)
    }
    if metadata.is_directory() {
      raise cache_failure("cache input is directory: `\{path.as_string()}`")
    } else if !metadata.is_file() {
      raise cache_failure("cache input is not a file: `\{path.as_string()}`")
    }
    let hasher = @cache.ContentHasher::new()
    @host.stream_file(
      effects,
      path,
      fn(chunk) { hasher.update(chunk) },
      chunk_size=64 * 1024,
    ) catch {
      error =>
        raise runtime_failure(@executor.ExecutionError::host(error), [], [], 0)
    }
    inputs.push(
      @cache.InputDigest::new(relative, hasher.finalize()) catch {
        _ => raise cache_failure("invalid cache input")
      },
    )
  }
  @cache.CacheKey::new(
    directive.recipe(),
    directive.body(),
    directive.interpreter(),
    interpreter_arguments=directive.interpreter_arguments().to_owned(),
    environment=directive.environment().to_owned(),
    extension=directive.extension(),
    working_directory=directive.working_directory().as_string(),
    positional=directive.positional().to_owned(),
    extra=directive.extra(),
    inputs~,
    outputs=directive.outputs().to_owned(),
  ) catch {
    _ => raise cache_failure("invalid cache key")
  }
}

///|
fn[H : @host.HostFs] cache_outputs_exist(
  effects : H,
  directive : @executor.CacheDirective,
) -> Bool raise RuntimeError {
  for relative in directive.outputs() {
    let path = cache_path(directive.working_directory(), relative)
    let exists = @host.HostFs::file_exists(effects, path) catch {
      error =>
        raise runtime_failure(@executor.ExecutionError::host(error), [], [], 0)
    }
    if !exists {
      return false
    }
  }
  true
}

///|
async fn[
  P : @host.HostAsyncProcess,
  S : @host.HostFs + @host.HostAsyncScriptTemp + @host.HostCacheStore,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] execute_cached_task(
  process : P,
  scripts : S,
  effects : H,
  task : @executor.ExecutionTask,
  options : @executor.ExecutionOptions,
  directory : @path.PathValue,
  directive : @executor.CacheDirective,
) -> @executor.ExecutionReport raise RuntimeError {
  let key = cache_key(scripts, directive)
  let digest = key.digest()
  let verbose : Array[Byte] = []
  if options.verbose() {
    for byte in running_message(directive.recipe(), options.color_enabled()) {
      verbose.push(byte)
    }
  }
  for byte in task.preamble() {
    verbose.push(byte)
  }
  if options.verbosity() >= 2 {
    for
      byte in @utf8.encode(
        "===> cache key \{digest}:\n" + key.debug_json() + "\n\n\n\n",
      ) {
      verbose.push(byte)
    }
  }
  let lease = @host.HostCacheStore::acquire_cache_lease(
    scripts, directory, digest,
  ) catch {
    error =>
      raise runtime_failure(@executor.ExecutionError::host(error), [], [], 0)
  }
  try
    @async.with_task_group() <| group => {
      group.add_defer(() => {
        try
          @async.protect_from_cancel(
            () => @host.HostCacheStore::release_cache_lease(scripts, lease),
            resume_on_cancel=false,
          )
        catch {
          _ => ()
        } noraise {
          _ => ()
        }
      })
      let stored = @host.HostCacheStore::read_cache_manifest(scripts, lease) catch {
        error =>
          raise runtime_failure(
            @executor.ExecutionError::host(error),
            [],
            [],
            0,
          )
      }
      let hit = match stored {
        Some(bytes) => {
          let decoded = try @utf8.decode(bytes) catch {
            _ => None
          } noraise {
            text => Some(text)
          }
          match decoded {
            Some(text) =>
              try {
                ignore(
                  @cache.validate_manifest(
                    text,
                    digest,
                    directive.recipe(),
                    directive.outputs(),
                  ),
                )
                cache_outputs_exist(scripts, directive)
              } catch {
                _ => false
              }
            None => false
          }
        }
        None => false
      }
      if hit {
        if options.verbose() {
          for byte in @utf8.encode("===> cache hit, skipping invocation\n") {
            verbose.push(byte)
          }
        }
        return @executor.ExecutionReport::new(
          b"",
          Bytes::from_array(verbose.copy()),
          0,
        )
      }
      @host.HostCacheStore::write_cache_manifest(scripts, lease, b"") catch {
        error =>
          raise runtime_failure(
            @executor.ExecutionError::host(error),
            [],
            [],
            0,
          )
      }
      let mut report = prepend_report_stderr(
        Bytes::from_array(verbose.copy())[:],
        execute_steps(process, scripts, effects, task.steps(), options, b""[:]),
      )
      if options.verbosity() >= 2 {
        report = append_report_stderr(report, b"\n"[:])
      }
      if !cache_outputs_exist(scripts, directive) {
        let output = directive.outputs().get(0).unwrap_or("")
        raise failure_after_report(
          CacheFailure(
            message="recipe `\{directive.recipe()}` failed to create cache output `\{output}`",
          ),
          report,
        )
      }
      let manifest = @cache.CacheManifest::new(
        digest,
        directive.recipe(),
        directive.outputs(),
      ) catch {
        _ =>
          raise failure_after_report(
            @executor.ExecutionError::host(
              InvalidInput("invalid cache manifest"),
            ),
            report,
          )
      }
      @host.HostCacheStore::write_cache_manifest(
        scripts,
        lease,
        @utf8.encode(manifest.encode()),
      ) catch {
        error =>
          raise Execution(
            error=@executor.ExecutionError::host(error),
            stdout=report.stdout().to_owned(),
            stderr=report.stderr().to_owned(),
            commands=report.commands(),
          )
      }
      report
    }
  catch {
    Execution(..) as failure => raise failure
    _ => raise cache_failure("cache task failed")
  } noraise {
    value => value
  }
}

///|
async fn[
  P : @host.HostAsyncProcess,
  S : @host.HostFs + @host.HostAsyncScriptTemp + @host.HostCacheStore,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] execute_task(
  process : P,
  scripts : S,
  effects : H,
  task : @executor.ExecutionTask,
  plan : @executor.ExecutionPlan,
) -> @executor.ExecutionReport raise RuntimeError {
  guard task.cache() is Some(directive) &&
    plan.options().cache_enabled() &&
    !plan.options().dry_run() else {
    let report = execute_steps(
      process,
      scripts,
      effects,
      task.steps(),
      plan.options(),
      b""[:],
    )
    let prefix : Array[Byte] = []
    if plan.options().verbose() && !task.steps().is_empty() {
      for byte in running_message(task.recipe(), plan.options().color_enabled()) {
        prefix.push(byte)
      }
    }
    for byte in task.preamble() {
      prefix.push(byte)
    }
    if !prefix.is_empty() {
      return prepend_report_stderr(Bytes::from_array(prefix)[:], report)
    }
    return report
  }
  guard plan.cache_directory() is Some(directory) else {
    raise invalid_plan("cached task has no cache directory")
  }
  execute_cached_task(
    process,
    scripts,
    effects,
    task,
    plan.options(),
    directory,
    directive,
  )
}

///|
/// Execute a prevalidated recipe DAG through a bounded FIFO semaphore. Task
/// output and failure selection are merged by stable plan order, never by
/// completion timing. Structured cancellation terminates child processes and
/// runs temporary-script cleanup before the task group exits.
pub async fn[
  P : @host.HostAsyncProcess,
  S : @host.HostFs + @host.HostAsyncScriptTemp + @host.HostCacheStore,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] execute_plan(
  process : P,
  scripts : S,
  effects : H,
  plan : @executor.ExecutionPlan,
) -> @executor.ExecutionReport raise RuntimeError {
  if plan.tasks().is_empty() {
    return execute_steps(
      process,
      scripts,
      effects,
      plan.steps(),
      plan.options(),
      plan.stderr(),
    )
  }
  let jobs = plan.options().jobs()
  if jobs <= 0 {
    raise invalid_plan("execution plan jobs must be positive")
  }
  let specs : Array[@scheduler.TaskSpec] = []
  for index, task in plan.tasks() {
    if task.id() != index {
      raise invalid_plan("execution task ids must be dense and ordered")
    }
    for dependency in task.dependencies() {
      if dependency >= task.id() {
        raise invalid_plan("execution task dependencies must precede the task")
      }
    }
    specs.push(
      @scheduler.TaskSpec::new(
        task.id(),
        task.order(),
        dependencies=task.dependencies().to_owned(),
      ),
    )
  }
  let schedule = @scheduler.build_schedule(specs, jobs) catch {
    _ => raise invalid_plan("invalid execution task graph")
  }
  let outcomes = try
    @async.with_task_group() <| group => {
      let semaphore = @async.Semaphore(jobs)
      let handles : Array[@async.Task[TaskOutcome]] = []
      for task in plan.tasks() {
        let dependencies : Array[@async.Task[TaskOutcome]] = []
        for dependency in task.dependencies() {
          dependencies.push(handles[dependency])
        }
        handles.push(
          group.spawn(() => {
            for dependency in dependencies {
              match dependency.wait() {
                Completed(_) => ()
                Failed(_) | Blocked => return Blocked
              }
            }
            semaphore.acquire()
            defer semaphore.release()
            try execute_task(process, scripts, effects, task, plan) catch {
              error => Failed(error)
            } noraise {
              report => Completed(report)
            }
          }),
        )
      }
      let result : Array[TaskOutcome] = []
      for handle in handles {
        result.push(handle.wait())
      }
      result
    }
  catch {
    Execution(..) as failure => raise failure
    _ => raise invalid_plan("execution task group failed")
  } noraise {
    value => value
  }
  let stdout : Array[Byte] = []
  let stderr : Array[Byte] = []
  for byte in plan.stderr() {
    stderr.push(byte)
  }
  let mut commands = 0
  for id in schedule.order() {
    match outcomes[id] {
      Completed(report) => commands += append_report(stdout, stderr, report)
      Failed(failure) => {
        for byte in failure.stdout() {
          stdout.push(byte)
        }
        for byte in failure.stderr() {
          stderr.push(byte)
        }
        commands += failure.commands()
        raise runtime_failure(failure.error(), stdout, stderr, commands)
      }
      Blocked => ()
    }
  }
  @executor.ExecutionReport::new(
    Bytes::from_array(stdout),
    Bytes::from_array(stderr),
    commands,
  )
}

///|
fn live_cache_failure(
  message : String,
  commands? : Int = 0,
) -> LiveRuntimeError {
  live_failure(CacheFailure(message~), commands)
}

///|
fn live_cache_path(
  base : @path.PathValue,
  relative : String,
) -> @path.PathValue raise LiveRuntimeError {
  let child = @path.PathValue::new(relative, base.flavor()) catch {
    _ => raise live_cache_failure("invalid cache path `\{relative}`")
  }
  base.join(child) catch {
    _ => raise live_cache_failure("cache path flavor mismatch")
  }
}

///|
fn[H : @host.HostFs] live_cache_key(
  effects : H,
  directive : @executor.CacheDirective,
) -> @cache.CacheKey raise LiveRuntimeError {
  let inputs : Array[@cache.InputDigest] = []
  for relative in directive.inputs() {
    let path = live_cache_path(directive.working_directory(), relative)
    let exists = @host.HostFs::file_exists(effects, path) catch {
      error => raise live_failure(@executor.ExecutionError::host(error), 0)
    }
    if !exists {
      raise live_cache_failure(
        "cache input does not exist: `\{path.as_string()}`",
      )
    }
    let metadata = @host.HostFs::metadata(effects, path) catch {
      NotFound(_) =>
        raise live_cache_failure(
          "cache input does not exist: `\{path.as_string()}`",
        )
      error => raise live_failure(@executor.ExecutionError::host(error), 0)
    }
    if metadata.is_directory() {
      raise live_cache_failure(
        "cache input is directory: `\{path.as_string()}`",
      )
    } else if !metadata.is_file() {
      raise live_cache_failure(
        "cache input is not a file: `\{path.as_string()}`",
      )
    }
    let hasher = @cache.ContentHasher::new()
    @host.stream_file(
      effects,
      path,
      fn(chunk) { hasher.update(chunk) },
      chunk_size=64 * 1024,
    ) catch {
      error => raise live_failure(@executor.ExecutionError::host(error), 0)
    }
    inputs.push(
      @cache.InputDigest::new(relative, hasher.finalize()) catch {
        _ => raise live_cache_failure("invalid cache input")
      },
    )
  }
  @cache.CacheKey::new(
    directive.recipe(),
    directive.body(),
    directive.interpreter(),
    interpreter_arguments=directive.interpreter_arguments().to_owned(),
    environment=directive.environment().to_owned(),
    extension=directive.extension(),
    working_directory=directive.working_directory().as_string(),
    positional=directive.positional().to_owned(),
    extra=directive.extra(),
    inputs~,
    outputs=directive.outputs().to_owned(),
  ) catch {
    _ => raise live_cache_failure("invalid cache key")
  }
}

///|
fn[H : @host.HostFs] live_cache_outputs_exist(
  effects : H,
  directive : @executor.CacheDirective,
) -> Bool raise LiveRuntimeError {
  for relative in directive.outputs() {
    let path = live_cache_path(directive.working_directory(), relative)
    let exists = @host.HostFs::file_exists(effects, path) catch {
      error => raise live_failure(@executor.ExecutionError::host(error), 0)
    }
    if !exists {
      return false
    }
  }
  true
}

///|
async fn[
  P : @host.HostAsyncProcess,
  O : @host.HostAsyncOutput,
  S : @host.HostFs + @host.HostAsyncScriptTemp + @host.HostCacheStore,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] execute_live_cached_task(
  process : P,
  output : O,
  scripts : S,
  effects : H,
  task : @executor.ExecutionTask,
  options : @executor.ExecutionOptions,
  directory : @path.PathValue,
  directive : @executor.CacheDirective,
) -> ExecutionSummary raise LiveRuntimeError {
  let key = live_cache_key(scripts, directive)
  let digest = key.digest()
  if options.verbose() {
    ignore(
      emit_live(
        output,
        Stderr,
        running_message(directive.recipe(), options.color_enabled())[:],
        0,
      ),
    )
  }
  ignore(emit_live(output, Stderr, task.preamble(), 0))
  if options.verbosity() >= 2 {
    ignore(
      emit_live(
        output,
        Stderr,
        @utf8.encode(
          "===> cache key \{digest}:\n" + key.debug_json() + "\n\n\n\n",
        )[:],
        0,
      ),
    )
  }
  let lease = @host.HostCacheStore::acquire_cache_lease(
    scripts, directory, digest,
  ) catch {
    error => raise live_failure(@executor.ExecutionError::host(error), 0)
  }
  try
    @async.with_task_group() <| group => {
      group.add_defer(() => {
        try
          @async.protect_from_cancel(
            () => @host.HostCacheStore::release_cache_lease(scripts, lease),
            resume_on_cancel=false,
          )
        catch {
          _ => ()
        } noraise {
          _ => ()
        }
      })
      let stored = @host.HostCacheStore::read_cache_manifest(scripts, lease) catch {
        error => raise live_failure(@executor.ExecutionError::host(error), 0)
      }
      let hit = match stored {
        Some(bytes) => {
          let decoded = try @utf8.decode(bytes) catch {
            _ => None
          } noraise {
            text => Some(text)
          }
          match decoded {
            Some(text) =>
              try {
                ignore(
                  @cache.validate_manifest(
                    text,
                    digest,
                    directive.recipe(),
                    directive.outputs(),
                  ),
                )
                live_cache_outputs_exist(scripts, directive)
              } catch {
                _ => false
              }
            None => false
          }
        }
        None => false
      }
      if hit {
        if options.verbose() {
          ignore(
            emit_live(
              output,
              Stderr,
              @utf8.encode("===> cache hit, skipping invocation\n")[:],
              0,
            ),
          )
        }
        return ExecutionSummary::{ commands: 0 }
      }
      @host.HostCacheStore::write_cache_manifest(scripts, lease, b"") catch {
        error => raise live_failure(@executor.ExecutionError::host(error), 0)
      }
      let summary = execute_live_steps(
        process,
        output,
        scripts,
        effects,
        task.steps(),
        options,
        b""[:],
      )
      if options.verbosity() >= 2 {
        ignore(emit_live(output, Stderr, b"\n"[:], summary.commands()))
      }
      if !live_cache_outputs_exist(scripts, directive) {
        let missing = directive.outputs().get(0).unwrap_or("")
        raise live_failure(
          CacheFailure(
            message="recipe `\{directive.recipe()}` failed to create cache output `\{missing}`",
          ),
          summary.commands(),
        )
      }
      let manifest = @cache.CacheManifest::new(
        digest,
        directive.recipe(),
        directive.outputs(),
      ) catch {
        _ =>
          raise live_cache_failure(
            "invalid cache manifest",
            commands=summary.commands(),
          )
      }
      @host.HostCacheStore::write_cache_manifest(
        scripts,
        lease,
        @utf8.encode(manifest.encode()),
      ) catch {
        error =>
          raise live_failure(
            @executor.ExecutionError::host(error),
            summary.commands(),
          )
      }
      summary
    }
  catch {
    LiveExecution(..) as failure => raise failure
    _ => raise live_cache_failure("cache task failed")
  } noraise {
    value => value
  }
}

///|
async fn[
  P : @host.HostAsyncProcess,
  O : @host.HostAsyncOutput,
  S : @host.HostFs + @host.HostAsyncScriptTemp + @host.HostCacheStore,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] execute_live_task(
  process : P,
  output : O,
  scripts : S,
  effects : H,
  task : @executor.ExecutionTask,
  plan : @executor.ExecutionPlan,
) -> ExecutionSummary raise LiveRuntimeError {
  guard task.cache() is Some(directive) &&
    plan.options().cache_enabled() &&
    !plan.options().dry_run() else {
    if plan.options().verbose() && !task.steps().is_empty() {
      ignore(
        emit_live(
          output,
          Stderr,
          running_message(task.recipe(), plan.options().color_enabled())[:],
          0,
        ),
      )
    }
    ignore(emit_live(output, Stderr, task.preamble(), 0))
    return try
      execute_live_steps(
        process,
        output,
        scripts,
        effects,
        task.steps(),
        plan.options(),
        b""[:],
      )
    catch {
      error => raise error.with_recipe_exit_message(task.print_exit_message())
    } noraise {
      summary => summary
    }
  }
  guard plan.cache_directory() is Some(directory) else {
    raise live_cache_failure("cached task has no cache directory")
  }
  try
    execute_live_cached_task(
      process,
      output,
      scripts,
      effects,
      task,
      plan.options(),
      directory,
      directive,
    )
  catch {
    error => raise error.with_recipe_exit_message(task.print_exit_message())
  } noraise {
    summary => summary
  }
}

///|
/// Execute a prevalidated recipe DAG with inherited child stdio. Runtime-owned
/// output is emitted before or after the corresponding process event and is
/// never replayed through an `ApplicationResponse`.
pub async fn[
  P : @host.HostAsyncProcess,
  O : @host.HostAsyncOutput,
  S : @host.HostFs + @host.HostAsyncScriptTemp + @host.HostCacheStore,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] execute_plan_live(
  process : P,
  output : O,
  scripts : S,
  effects : H,
  plan : @executor.ExecutionPlan,
) -> ExecutionSummary raise LiveRuntimeError {
  ignore(emit_live(output, Stderr, plan.stderr(), 0))
  if plan.tasks().is_empty() {
    return execute_live_steps(
      process,
      output,
      scripts,
      effects,
      plan.steps(),
      plan.options(),
      b""[:],
    )
  }
  let jobs = plan.options().jobs()
  if jobs <= 0 {
    raise live_cache_failure("execution plan jobs must be positive")
  }
  let specs : Array[@scheduler.TaskSpec] = []
  for index, task in plan.tasks() {
    if task.id() != index {
      raise live_cache_failure("execution task ids must be dense and ordered")
    }
    for dependency in task.dependencies() {
      if dependency >= task.id() {
        raise live_cache_failure(
          "execution task dependencies must precede the task",
        )
      }
    }
    specs.push(
      @scheduler.TaskSpec::new(
        task.id(),
        task.order(),
        dependencies=task.dependencies().to_owned(),
      ),
    )
  }
  let schedule = @scheduler.build_schedule(specs, jobs) catch {
    _ => raise live_cache_failure("invalid execution task graph")
  }
  let outcomes = try
    @async.with_task_group() <| group => {
      let semaphore = @async.Semaphore(jobs)
      let handles : Array[@async.Task[LiveTaskOutcome]] = []
      for task in plan.tasks() {
        let dependencies : Array[@async.Task[LiveTaskOutcome]] = []
        for dependency in task.dependencies() {
          dependencies.push(handles[dependency])
        }
        handles.push(
          group.spawn(() => {
            for dependency in dependencies {
              match dependency.wait() {
                LiveCompleted(_) => ()
                LiveFailed(_) | LiveBlocked => return LiveBlocked
              }
            }
            semaphore.acquire()
            defer semaphore.release()
            try
              execute_live_task(process, output, scripts, effects, task, plan)
            catch {
              error => LiveFailed(error)
            } noraise {
              summary => LiveCompleted(summary)
            }
          }),
        )
      }
      let result : Array[LiveTaskOutcome] = []
      for handle in handles {
        result.push(handle.wait())
      }
      result
    }
  catch {
    LiveExecution(..) as failure => raise failure
    _ => raise live_cache_failure("execution task group failed")
  } noraise {
    value => value
  }
  let mut commands = 0
  for id in schedule.order() {
    match outcomes[id] {
      LiveCompleted(summary) => commands += summary.commands()
      LiveFailed(failure) =>
        raise live_failure(
          failure.error(),
          commands + failure.commands(),
          show_message=failure.show_message(),
        )
      LiveBlocked => ()
    }
  }
  { commands, }
}
