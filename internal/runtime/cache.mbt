///|
fn invalid_plan(message : String) -> RuntimeError {
  runtime_failure(
    @planner.ExecutionError::host(InvalidInput(message)),
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
  report : @planner.ExecutionReport,
) -> @planner.ExecutionReport {
  let stderr : Array[Byte] = []
  for byte in prefix {
    stderr.push(byte)
  }
  for byte in report.stderr() {
    stderr.push(byte)
  }
  @planner.ExecutionReport::new(
    report.stdout().to_owned(),
    Bytes::from_array(stderr),
    report.commands(),
  )
}

///|
fn append_report_stderr(
  report : @planner.ExecutionReport,
  suffix : BytesView,
) -> @planner.ExecutionReport {
  let stderr = report.stderr().to_array()
  for byte in suffix {
    stderr.push(byte)
  }
  @planner.ExecutionReport::new(
    report.stdout().to_owned(),
    Bytes::from_array(stderr),
    report.commands(),
  )
}

///|
fn failure_after_report(
  error : @planner.ExecutionError,
  report : @planner.ExecutionReport,
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
  directive : @planner.CacheDirective,
) -> @cache.CacheKey raise RuntimeError {
  let inputs : Array[@cache.InputDigest] = []
  for relative in directive.inputs() {
    let path = cache_path(directive.working_directory(), relative)
    let exists = @host.HostFs::file_exists(effects, path) catch {
      error =>
        raise runtime_failure(@planner.ExecutionError::host(error), [], [], 0)
    }
    if !exists {
      raise cache_failure("cache input does not exist: `\{path.as_string()}`")
    }
    let metadata = @host.HostFs::metadata(effects, path) catch {
      NotFound(_) =>
        raise cache_failure("cache input does not exist: `\{path.as_string()}`")
      error =>
        raise runtime_failure(@planner.ExecutionError::host(error), [], [], 0)
    }
    if metadata.is_directory() {
      raise cache_failure("cache input is directory: `\{path.as_string()}`")
    } else if !metadata.is_file() {
      raise cache_failure("cache input is not a file: `\{path.as_string()}`")
    }
    let hasher = @cache.ContentHasher::new()
    @host_fs.stream_file(
      effects,
      path,
      fn(chunk) { hasher.update(chunk) },
      chunk_size=64 * 1024,
    ) catch {
      error =>
        raise runtime_failure(@planner.ExecutionError::host(error), [], [], 0)
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
  directive : @planner.CacheDirective,
) -> Bool raise RuntimeError {
  for relative in directive.outputs() {
    let path = cache_path(directive.working_directory(), relative)
    let exists = @host.HostFs::file_exists(effects, path) catch {
      error =>
        raise runtime_failure(@planner.ExecutionError::host(error), [], [], 0)
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
  task : @planner.ExecutionTask,
  options : @planner.ExecutionOptions,
  directory : @path.PathValue,
  directive : @planner.CacheDirective,
) -> @planner.ExecutionReport raise RuntimeError {
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
      raise runtime_failure(@planner.ExecutionError::host(error), [], [], 0)
  }
  try
    @async.with_task_group() <| group => {
      group.add_defer(() => {
        try
          @async.protect_from_cancel(() => {
            @host.HostCacheStore::release_cache_lease(scripts, lease)
          })
        catch {
          _ => ()
        } noraise {
          _ => ()
        }
      })
      let stored = @host.HostCacheStore::read_cache_manifest(scripts, lease) catch {
        error =>
          raise runtime_failure(@planner.ExecutionError::host(error), [], [], 0)
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
        return @planner.ExecutionReport::new(
          b"",
          Bytes::from_array(verbose.copy()),
          0,
        )
      }
      @host.HostCacheStore::write_cache_manifest(scripts, lease, b"") catch {
        error =>
          raise runtime_failure(@planner.ExecutionError::host(error), [], [], 0)
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
            @planner.ExecutionError::host(
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
            error=@planner.ExecutionError::host(error),
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
  task : @planner.ExecutionTask,
  plan : @planner.ExecutionPlan,
) -> @planner.ExecutionReport raise RuntimeError {
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
/// Execute a prevalidated recipe DAG through the shared deterministic
/// coordinator. Task output and failure selection are merged by stable plan
/// order, never by completion timing. Structured cancellation terminates child
/// processes and runs temporary-script cleanup before the task group exits.
