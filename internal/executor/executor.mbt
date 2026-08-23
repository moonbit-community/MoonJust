///|
/// Execute the ordinary line-oriented body of one recipe in source order.
///
/// Static parsing, semantic validation, invocation selection, and environment
/// composition happen before this boundary. A dry run evaluates and echoes
/// every line but never invokes `HostProcess`.
pub fn[T : @host.HostProcess] execute_recipe_lines(
  host : T,
  recipe : @syntax.Recipe,
  environment : @evaluator.Environment,
  shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  process_environment? : ArrayView[(String, String)] = [],
  options? : ExecutionOptions = ExecutionOptions::new(),
) -> ExecutionReport raise ExecutionError {
  let stdout : Array[Byte] = []
  let stderr : Array[Byte] = []
  let mut commands = 0
  for index, source_line in recipe.lines() {
    let line = evaluate_line(source_line, environment)
    let should_echo = options.dry_run() ||
      options.verbose() ||
      options.timestamp() is Some(_) ||
      (!options.quiet() && !recipe.quiet() && !line.quiet)
    if should_echo {
      append_bytes(
        stderr,
        render_command_echo(
          line.command,
          timestamp=options.timestamp(),
          color=options.command_color(),
        )[:],
      )
    }
    if options.dry_run() {
      continue
    }
    let spec = command_spec(
      shell,
      line.command,
      cwd,
      process_environment,
      options.quiet(),
    )
    let result = @host.HostProcess::run_process(host, spec) catch {
      error => raise Host(error)
    }
    commands += 1
    append_bytes(stdout, result.stdout())
    append_bytes(stderr, result.stderr())
    match result.termination() {
      Exited(0) => ()
      Exited(_) if line.ignore_error => ()
      Exited(exit_code) =>
        raise CommandFailed(recipe=recipe.name(), line=index + 1, exit_code~)
      Signaled(_) if line.ignore_error => ()
      Signaled(signal) =>
        raise CommandSignaled(recipe=recipe.name(), line=index + 1, signal~)
      Interrupted(_) if line.ignore_error => ()
      Interrupted(signal) => raise Interrupted(signal~)
    }
  }
  ExecutionReport::new(
    Bytes::from_array(stdout),
    Bytes::from_array(stderr),
    commands,
  )
}

///|
/// Effect-enabled line execution used once a runtime grants the complete
/// evaluator host contract. It mirrors `execute_recipe_lines` while allowing
/// backticks and effectful shell builtins in interpolations.
pub fn[
  T : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostProcess + @host.HostPlatform + @host.HostTerminal,
] execute_recipe_lines_effectful(
  host : T,
  recipe : @syntax.Recipe,
  environment : @evaluator.Environment,
  shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  process_environment? : ArrayView[(String, String)] = [],
  options? : ExecutionOptions = ExecutionOptions::new(),
) -> ExecutionReport raise ExecutionError {
  let stdout : Array[Byte] = []
  let stderr : Array[Byte] = []
  let mut commands = 0
  for index, source_line in recipe.lines() {
    let rendered = if options.dry_run() {
      render_line(source_line, environment)
    } else {
      render_effectful_line(
        host,
        source_line,
        environment,
        cwd,
        shell,
        options.quiet(),
      )
    }
    let mut offset = 0
    let mut quiet = false
    let mut ignore_error = false
    while offset < rendered.length() {
      match rendered.unsafe_get(offset) {
        '@' => {
          quiet = true
          offset += 1
        }
        '-' => {
          ignore_error = true
          offset += 1
        }
        _ => break
      }
    }
    let command = rendered.view(start_offset=offset).to_owned()
    if options.dry_run() ||
      options.verbose() ||
      options.timestamp() is Some(_) ||
      (!options.quiet() && !recipe.quiet() && !quiet) {
      append_bytes(
        stderr,
        render_command_echo(
          command,
          timestamp=options.timestamp(),
          color=options.command_color(),
        )[:],
      )
    }
    if options.dry_run() {
      continue
    }
    let spec = command_spec(
      shell,
      command,
      cwd,
      process_environment,
      options.quiet(),
    )
    let result = @host.HostProcess::run_process(host, spec) catch {
      error => raise Host(error)
    }
    commands += 1
    append_bytes(stdout, result.stdout())
    append_bytes(stderr, result.stderr())
    match result.termination() {
      Exited(0) => ()
      Exited(_) if ignore_error => ()
      Exited(exit_code) =>
        raise CommandFailed(recipe=recipe.name(), line=index + 1, exit_code~)
      Signaled(_) if ignore_error => ()
      Signaled(signal) =>
        raise CommandSignaled(recipe=recipe.name(), line=index + 1, signal~)
      Interrupted(_) if ignore_error => ()
      Interrupted(signal) => raise Interrupted(signal~)
    }
  }
  ExecutionReport::new(
    Bytes::from_array(stdout),
    Bytes::from_array(stderr),
    commands,
  )
}
