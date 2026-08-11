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
priv enum TaskOutcome {
  Completed(@executor.ExecutionReport)
  Failed(RuntimeError)
  Blocked
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
  for step in steps {
    let started = if options.time() { Some(@async.now()) } else { None }
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
  runtime_failure(
    @executor.ExecutionError::host(InvalidInput(message)),
    [],
    [],
    0,
  )
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
fn running_message(recipe : String) -> Bytes {
  @utf8.encode("===> running recipe `\{recipe}`...\n")
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
    let metadata = @host.HostFs::metadata(effects, path) catch {
      error =>
        raise runtime_failure(@executor.ExecutionError::host(error), [], [], 0)
    }
    if !metadata.is_file() {
      raise cache_failure("cache input `\{relative}` is not a file")
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
    for byte in running_message(directive.recipe()) {
      verbose.push(byte)
    }
  }
  if options.verbosity() >= 2 {
    for
      byte in @utf8.encode(
        "===> cache key \{digest}:\n" + key.debug_json() + "\n\n",
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
      let report = prepend_report_stderr(
        Bytes::from_array(verbose.copy())[:],
        execute_steps(process, scripts, effects, task.steps(), options, b""[:]),
      )
      if !cache_outputs_exist(scripts, directive) {
        raise failure_after_report(
          @executor.ExecutionError::host(
            InvalidInput(
              "cache outputs are missing after recipe `\{directive.recipe()}`",
            ),
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
    if plan.options().verbose() && !task.steps().is_empty() {
      return prepend_report_stderr(running_message(task.recipe())[:], report)
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
