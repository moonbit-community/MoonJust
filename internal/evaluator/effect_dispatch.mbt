///|
fn[T : @host.HostFs + @host.HostEnv + @host.HostPlatform] which_value(
  host : T,
  executable : String,
  context : EvaluationContext,
  span : @source.Span,
) -> String raise EvaluationError {
  if executable == "" {
    return ""
  }
  let path = @host.HostEnv::env_get(host, "PATH") catch {
    error => raise Host(error, span~)
  }
  let platform = @host.HostPlatform::platform_info(host) catch {
    error => raise Host(error, span~)
  }
  let pathext = if platform.operating_system() == Windows {
    @host.HostEnv::env_get(host, "PATHEXT") catch {
      error => raise Host(error, span~)
    }
  } else {
    None
  }
  for
    candidate in which_candidates(
      executable,
      context,
      path.unwrap_or(""),
      platform,
      pathext,
      span,
    ) {
    let exists = @host.HostFs::file_exists(host, candidate) catch {
      error => raise Host(error, span~)
    }
    if !exists {
      continue
    }
    let metadata = try @host.HostFs::metadata(host, candidate) catch {
      NotFound(_) => continue
      error => raise Host(error, span~)
    } noraise {
      value => value
    }
    let executable = if platform.operating_system() == Windows {
      windows_candidate_is_executable(candidate, metadata, pathext)
    } else {
      metadata.is_file() && metadata.is_executable()
    }
    if executable {
      return candidate.as_string()
    }
  }
  ""
}

///|
/// Invoke a builtin using explicit invocation facts and host capabilities.
pub fn[
  T : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] call_non_process_effect_with_context(
  host : T,
  requested : String,
  arguments : Array[Value],
  context : EvaluationContext,
  span : @source.Span,
) -> Value raise EvaluationError {
  let name = validate_effect_arity(requested, arguments, span)
  match context_builtin(name, arguments, context, span) {
    Some(value) => return value
    None => ()
  }
  match name {
    "arch" => {
      let platform = @host.HostPlatform::platform_info(host) catch {
        error => raise Host(error, span~)
      }
      String(platform.architecture())
    }
    "os" | "os_family" => {
      let platform = @host.HostPlatform::platform_info(host) catch {
        error => raise Host(error, span~)
      }
      let value = match platform.operating_system() {
        Linux => if name == "os_family" { "unix" } else { "linux" }
        Macos => if name == "os_family" { "unix" } else { "macos" }
        Windows => "windows"
        Other(value) => value
      }
      String(value)
    }
    "env" | "env_var" =>
      env_value(
        host,
        name,
        arguments[0],
        if name == "env" && arguments.length() == 2 {
          Some(arguments[1])
        } else {
          None
        },
        span,
      )
    "env_var_or_default" =>
      env_value(host, name, arguments[0], Some(arguments[1]), span)
    "absolute_path" =>
      if context.lists() {
        map_context_paths(arguments[0], context, span)
      } else {
        String(
          resolve_context_path(context, arguments[0].to_string(), span).as_string(),
        )
      }
    "canonicalize" => {
      let raw = expect_string(name, arguments, 0, span)
      let path = resolve_context_path(context, raw, span)
      let canonical = @host.HostFs::canonicalize(host, path) catch {
        error =>
          raise effect_failure(
            "call to function `canonicalize` failed: I/O error canonicalizing `" +
            raw +
            "`: " +
            canonicalize_host_error_detail(error, path),
            span,
          )
      }
      String(canonical.as_string())
    }
    "read" => {
      let raw = expect_string(name, arguments, 0, span)
      let path = resolve_context_path(context, raw, span)
      let bytes = @host.HostFs::read_file(host, path) catch {
        error =>
          raise effect_failure(
            "call to function `read` failed: I/O error reading `" +
            raw +
            "`: " +
            host_error_detail(error),
            span,
          )
      }
      String(bytes_text(bytes, span))
    }
    "sha256_file" => {
      let raw = expect_string(name, arguments, 0, span)
      let path = resolve_context_path(context, raw, span)
      let hasher = @builtin.Sha256Hasher::new()
      @host_fs.stream_file(host, path, fn(bytes) { hasher.update(bytes) }) catch {
        error => raise Host(error, span~)
      }
      String(hasher.finalize())
    }
    "blake3_file" => {
      let raw = expect_string(name, arguments, 0, span)
      let path = resolve_context_path(context, raw, span)
      let hasher = @builtin.Blake3Hasher::new()
      @host_fs.stream_file(host, path, fn(bytes) { hasher.update(bytes) }) catch {
        error => raise Host(error, span~)
      }
      String(hasher.finalize())
    }
    "path_exists" => {
      let raw = expect_string(name, arguments, 0, span)
      if raw == "" {
        return context_boolean(context, false)
      }
      let path = resolve_context_path(context, raw, span)
      context_boolean(
        context,
        @host.HostFs::file_exists(host, path) catch {
          error => raise Host(error, span~)
        },
      )
    }
    "write" => {
      let raw = expect_string(name, arguments, 0, span)
      let contents = expect_string(name, arguments, 1, span)
      let path = resolve_context_path(context, raw, span)
      @host.HostFs::write_file(host, path, @utf8.encode(contents)) catch {
        error => raise Host(error, span~)
      }
      String("")
    }
    "now_millis" => {
      let value = @host.HostClock::now_millis(host) catch {
        error => raise Host(error, span~)
      }
      String(value.to_string())
    }
    "datetime" | "datetime_utc" => {
      let value = @host.HostClock::now_millis(host) catch {
        error => raise Host(error, span~)
      }
      let format = expect_string(name, arguments, 0, span)
      String(
        format_datetime(
          value,
          if name == "datetime_utc" {
            0
          } else {
            require_context_int(
              "utc_offset_seconds",
              context.utc_offset_seconds,
              span,
            )
          },
          format,
          name,
          span,
        ),
      )
    }
    "choose" => choose_value(host, arguments, span)
    "uuid" => {
      let bytes = @host.HostRandom::random_bytes(host, 16) catch {
        error => raise Host(error, span~)
      }
      if bytes.length() != 16 {
        raise effect_failure(
          "random host returned an invalid UUID byte count", span,
        )
      }
      String(uuid_text(bytes))
    }
    "shell" => raise EffectRequired(effect="process", span~)
    "style" => style_value(host, arguments, context, span)
    "which" => {
      if !context.lists() {
        raise effect_failure(
          "the `which()` function requires `set lists`", span,
        )
      }
      let executable = expect_string(name, arguments, 0, span)
      let path = which_value(host, executable, context, span)
      if path.is_empty() {
        List([])
      } else {
        List([String(path)])
      }
    }
    "require" => {
      let executable = expect_string(name, arguments, 0, span)
      let path = which_value(host, executable, context, span)
      if path == "" {
        raise effect_failure(
          "call to function `require` failed: could not find executable `" +
          executable +
          "`",
          span,
        )
      }
      String(path)
    }
    _ =>
      @builtin.call(name, arguments) catch {
        error => raise Builtin(error, span~)
      }
  }
}

///|
/// Invoke an effectful builtin using a synchronous process capability.
pub fn[
  T : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostProcess + @host.HostPlatform + @host.HostTerminal,
] call_effect_with_context(
  host : T,
  requested : String,
  arguments : Array[Value],
  context : EvaluationContext,
  span : @source.Span,
) -> Value raise EvaluationError {
  if @builtin.canonical_name(requested) == "shell" {
    call_shell_effect(
      host,
      arguments,
      context,
      EffectShell::new("sh", ["-cu"]),
      span,
    )
  } else {
    call_non_process_effect_with_context(
      host, requested, arguments, context, span,
    )
  }
}

///|
/// Backwards-compatible cwd-only effect entry point. Context-only facts not
/// derivable from cwd remain explicit `MissingContext` errors.
pub fn[
  T : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostProcess + @host.HostPlatform + @host.HostTerminal,
] call_effect(
  host : T,
  name : String,
  arguments : Array[Value],
  cwd : @path.PathValue,
  span : @source.Span,
) -> Value raise EvaluationError {
  call_effect_with_context(
    host,
    name,
    arguments,
    EvaluationContext::new(
      cwd~,
      invocation_directory=cwd,
      invocation_directory_native=cwd,
    ),
    span,
  )
}

///|
pub fn[
  T : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostProcess + @host.HostPlatform + @host.HostTerminal,
] evaluate_backtick(
  host : T,
  command : String,
  cwd : @path.PathValue,
  span : @source.Span,
) -> Value raise EvaluationError {
  call_effect(host, "shell", [String(command)], cwd, span)
}

///|
pub fn[T : @host.HostProcess] evaluate_backtick_with_shell(
  host : T,
  command : String,
  context : EvaluationContext,
  shell : EffectShell,
  span : @source.Span,
  quiet? : Bool = false,
) -> Value raise EvaluationError {
  call_shell_effect(
    host,
    [String(command)],
    context,
    shell,
    span,
    quiet~,
    shell_function=false,
  )
}
