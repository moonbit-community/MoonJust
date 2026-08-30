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
  directive : @planner.CacheDirective,
) -> @cache.CacheKey raise LiveRuntimeError {
  let inputs : Array[@cache.InputDigest] = []
  for relative in directive.inputs() {
    let path = live_cache_path(directive.working_directory(), relative)
    let exists = @host.HostFs::file_exists(effects, path) catch {
      error => raise live_failure(@planner.ExecutionError::host(error), 0)
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
      error => raise live_failure(@planner.ExecutionError::host(error), 0)
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
    @host_fs.stream_file(
      effects,
      path,
      fn(chunk) { hasher.update(chunk) },
      chunk_size=64 * 1024,
    ) catch {
      error => raise live_failure(@planner.ExecutionError::host(error), 0)
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
  directive : @planner.CacheDirective,
) -> Bool raise LiveRuntimeError {
  for relative in directive.outputs() {
    let path = live_cache_path(directive.working_directory(), relative)
    let exists = @host.HostFs::file_exists(effects, path) catch {
      error => raise live_failure(@planner.ExecutionError::host(error), 0)
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
  task : @planner.ExecutionTask,
  options : @planner.ExecutionOptions,
  directory : @path.PathValue,
  directive : @planner.CacheDirective,
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
    error => raise live_failure(@planner.ExecutionError::host(error), 0)
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
        error => raise live_failure(@planner.ExecutionError::host(error), 0)
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
        return ExecutionSummary::{ commands: 0, }
      }
      @host.HostCacheStore::write_cache_manifest(scripts, lease, b"") catch {
        error => raise live_failure(@planner.ExecutionError::host(error), 0)
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
            @planner.ExecutionError::host(error),
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
  task : @planner.ExecutionTask,
  plan : @planner.ExecutionPlan,
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
