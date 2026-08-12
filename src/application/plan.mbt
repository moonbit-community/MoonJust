///|
fn evaluated_shell_setting(
  compilation : @semantic.Compilation,
  global : @evaluator.Environment,
  name : String,
) -> @environment.ShellConfiguration? raise ApplicationError {
  match compilation.settings().get(name) {
    Some(Text(program)) => {
      let arguments = if name == "shell" { ["-cu"] } else { [] }
      Some(
        @environment.ShellConfiguration::new(program, arguments) catch {
          error => raise Environment(error)
        },
      )
    }
    Some(Expression(expression)) => {
      let value = @evaluator.evaluate(expression, environment=global) catch {
        error => raise Evaluation(error)
      }
      guard value is List(values) else {
        raise Query("setting `\{name}` must evaluate to a string list")
      }
      let parts : Array[String] = []
      for value in values {
        match value {
          String(text) => parts.push(text)
          _ => raise Query("setting `\{name}` must evaluate to a string list")
        }
      }
      guard parts.get(0) is Some(program) else {
        raise Query("setting `\{name}` must not be empty")
      }
      Some(
        @environment.ShellConfiguration::new(program, parts[1:].to_owned()) catch {
          error => raise Environment(error)
        },
      )
    }
    _ => None
  }
}

///|
fn evaluated_string_setting(
  compilation : @semantic.Compilation,
  global : @evaluator.Environment,
  name : String,
) -> String? raise ApplicationError {
  match compilation.settings().get(name) {
    Some(Text(value)) => Some(value)
    Some(Expression(expression)) => {
      let value = @evaluator.evaluate(expression, environment=global) catch {
        error => raise Evaluation(error)
      }
      match value {
        String(value) => Some(value)
        _ => raise Query("setting `\{name}` must evaluate to a string")
      }
    }
    _ => None
  }
}

///|
fn selected_shell(
  compilation : @semantic.Compilation,
  global : @evaluator.Environment,
  arguments : @cli.CliArguments,
  flavor : @path.PathFlavor,
) -> @environment.ShellConfiguration raise ApplicationError {
  let info = if flavor == Windows {
    @host.PlatformInfo::new(Windows, "unknown", Windows)
  } else {
    @host.PlatformInfo::new(Other("unix"), "unknown", Unix)
  }
  let platform = @environment.PlatformConfiguration::new(info)
  let setting_shell = evaluated_shell_setting(compilation, global, "shell")
  let windows_shell = evaluated_shell_setting(
    compilation, global, "windows-shell",
  )
  @environment.resolve_shell(
    platform,
    cli_shell=arguments.value("shell"),
    cli_arguments=arguments.shell_arguments(),
    setting_shell~,
    windows_shell~,
    windows_powershell=compilation.settings().bool("windows-powershell"),
  ) catch {
    error => raise Environment(error)
  }
}

///|
fn[T : @host.HostTerminal] selected_command_color(
  effects : T,
  arguments : @cli.CliArguments,
) -> @executor.CommandColor? raise ApplicationError {
  let mode = arguments.value("color").unwrap_or("auto")
  let active = match mode {
    "always" => true
    "never" => false
    "auto" => {
      let terminal = @host.HostTerminal::terminal_info(effects) catch {
        error => raise Host(error)
      }
      terminal.color_supported() && terminal.stderr_is_terminal()
    }
    _ => raise Query("invalid --color value")
  }
  if !active {
    return None
  }
  guard arguments.value("command-color") is Some(value) else {
    return Some(Bold)
  }
  match value {
    "black" => Some(Black)
    "red" => Some(Red)
    "green" => Some(Green)
    "yellow" => Some(Yellow)
    "blue" => Some(Blue)
    "purple" => Some(Magenta)
    "cyan" => Some(Cyan)
    _ => raise Query("invalid --command-color value")
  }
}

///|
fn selected_jobs(arguments : @cli.CliArguments) -> Int raise ApplicationError {
  guard arguments.value("jobs") is Some(value) else { return 1 }
  let jobs = @string.parse_int(value[:]) catch {
    _ =>
      raise Query(
        "invalid --jobs value `\{value}`; expected a positive integer",
      )
  }
  if jobs <= 0 {
    raise Query("invalid --jobs value `\{value}`; expected a positive integer")
  }
  jobs
}

///|
fn execution_options(
  arguments : @cli.CliArguments,
  timestamp : String?,
  command_color : @executor.CommandColor?,
) -> @executor.ExecutionOptions raise ApplicationError {
  @executor.ExecutionOptions::from_values(
    arguments.flag("dry-run"),
    arguments.flag("quiet"),
    arguments.flag("verbose"),
    arguments.flag("time"),
    timestamp,
    command_color,
  )
  .with_jobs(selected_jobs(arguments))
  .with_cache(!arguments.flag("no-cache"))
  .with_unstable(arguments.flag("unstable"))
  .with_verbosity(arguments.count("verbose"))
}

///|
fn cache_directory(
  project : @path.PathValue,
) -> @path.PathValue raise ApplicationError {
  let relative = @path.PathValue::new(".moonjust-cache/v1", project.flavor()) catch {
    error => raise Path(error)
  }
  project.join(relative) catch {
    error => raise Path(error)
  }
}

///|
fn[H : @host.HostClock] selected_timestamp(
  effects : H,
  arguments : @cli.CliArguments,
) -> String? raise ApplicationError {
  if !arguments.flag("timestamp") {
    return None
  }
  let millis = @host.HostClock::now_millis(effects) catch {
    error => raise Host(error)
  }
  Some(
    @executor.format_timestamp(
      millis,
      arguments.value("timestamp-format").unwrap_or("%H:%M:%S"),
    ),
  )
}

///|
fn invocation_values(
  compilation : @semantic.Compilation,
  invocation : @invocation.Invocation,
  global : @evaluator.Environment,
) -> Array[@value.Value] raise ApplicationError {
  guard compilation.recipe(invocation.recipe()) is Some(recipe) else {
    raise Query("recipe `\{invocation.recipe()}` does not exist")
  }
  let scope = @evaluator.Environment::child(global)
  let result : Array[@value.Value] = []
  for index, parameter in recipe.parameters() {
    let elements = invocation.arguments()[index].elements()
    if parameter.variadic() {
      for element in elements {
        result.push(String(element))
      }
      scope.set(
        parameter.name(),
        List(elements.map(fn(element) { String(element) })),
      )
    } else {
      let value = match elements.length() {
        0 =>
          match parameter.default_value() {
            Some(expression) =>
              @evaluator.evaluate(expression, environment=scope) catch {
                error => raise Evaluation(error)
              }
            None => String("")
          }
        1 => String(elements[0])
        _ => List(elements.map(fn(element) { String(element) }))
      }
      result.push(value)
      scope.set(parameter.name(), value)
    }
  }
  result
}

///|
fn[T : @host.HostEnv] process_environment(
  host : T,
  global : @evaluator.Environment,
  flavor : @path.PathFlavor,
) -> Array[(String, String)] raise ApplicationError {
  let mode : @environment.EnvNameMode = if flavor == Windows {
    AsciiInsensitive
  } else {
    Sensitive
  }
  let table = @environment.snapshot(host, name_mode=mode) catch {
    error => raise Host(error)
  }
  for name in global.names() {
    if global.is_exported(name) {
      match global.get(name) {
        Some(value) => table.set(name, value.to_string())
        None => ()
      }
    }
  }
  table.entries()
}

///|
fn setting_string_values(
  compilation : @semantic.Compilation,
  global : @evaluator.Environment,
  name : String,
) -> Array[String] raise ApplicationError {
  match compilation.settings().get(name) {
    Some(Text(value)) => [value]
    Some(Expression(expression)) => {
      let evaluated = @evaluator.evaluate(expression, environment=global) catch {
        error => raise Evaluation(error)
      }
      match evaluated {
        String(value) => [value]
        List(values) => values.map(fn(value) { value.to_string() })
        _ => []
      }
    }
    _ => []
  }
}

///|
fn[F : @host.HostFs] compose_dotenv_environment(
  filesystem : F,
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
  global : @evaluator.Environment,
  cwd : @path.PathValue,
  ambient_entries : ArrayView[(String, String)],
) -> Array[(String, String)] raise ApplicationError {
  let mode : @environment.EnvNameMode = if cwd.flavor() == Windows {
    AsciiInsensitive
  } else {
    Sensitive
  }
  let ambient = @environment.EnvTable::from_entries(
    ambient_entries,
    name_mode=mode,
  )
  let filenames = arguments.values("dotenv-filename").to_owned()
  if filenames.is_empty() {
    filenames.append(
      setting_string_values(compilation, global, "dotenv-filename"),
    )
  }
  let paths = arguments.values("dotenv-path").to_owned()
  if paths.is_empty() {
    paths.append(setting_string_values(compilation, global, "dotenv-path"))
  }
  let load = !arguments.flag("no-dotenv") &&
    (
      compilation.settings().bool("dotenv-load") ||
      compilation.settings().bool("dotenv-required") ||
      !filenames.is_empty() ||
      !paths.is_empty()
    )
  let dotenv = @environment.load_dotenv_files(
    filesystem,
    cwd,
    ambient,
    @environment.DotenvOptions::new(
      load~,
      override_environment=compilation.settings().bool("dotenv-override"),
      required=compilation.settings().bool("dotenv-required"),
      lists=compilation.settings().bool("lists"),
      dry_run=arguments.flag("dry-run"),
      filenames~,
      paths~,
    ),
  ) catch {
    error => raise Dotenv(error)
  }
  let result = ambient.entries()
  for entry in dotenv.entries() {
    let mut replaced = false
    for index, existing in result {
      if existing.0 == entry.0 {
        result[index] = entry
        replaced = true
        break
      }
    }
    if !replaced {
      result.push(entry)
    }
  }
  result
}

///|
/// Validate and plan a run command without granting process capability.
pub fn[F : @host.HostFs, E : @host.HostEnv + @host.HostTerminal] plan_run_command(
  host : F,
  environment_host : E,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @executor.ExecutionPlan raise ApplicationError {
  if arguments.command() != RunCommand {
    raise UnsupportedCommand("execution planning for non-run command")
  }
  let (loaded, directories) = load_input_with_directories(
    host, arguments, context,
  )
  let compilation = compile_loaded(loaded)
  let overrides = variable_overrides(compilation, arguments)
  let invocations = @invocation.parse_invocations(
    compilation,
    arguments.positional(),
    overrides~,
  ) catch {
    error => raise Invocation(error)
  }
  let global = @evaluator.evaluate_compilation(compilation, overrides~) catch {
    error => raise Evaluation(error)
  }
  let module_setting = evaluated_string_setting(
    compilation, global, "working-directory",
  )
  let requests : Array[@executor.RecipeRequest] = []
  for invocation in invocations {
    requests.push(
      @executor.RecipeRequest::new(
        invocation.recipe(),
        arguments=invocation_values(compilation, invocation, global),
      ),
    )
  }
  let shell = selected_shell(
    compilation,
    global,
    arguments,
    context.cwd().flavor(),
  )
  let cwd = directories.recipe_directory(
    module_setting~,
    module_no_cd=compilation.settings().bool("no-cd"),
  ) catch {
    error => raise WorkingDirectory(error)
  }
  let environment = process_environment(
    environment_host,
    global,
    context.cwd().flavor(),
  )
  let command_color = selected_command_color(environment_host, arguments)
  let options = execution_options(arguments, None, command_color)
  @executor.plan_recipe_graph(
    compilation,
    requests,
    global,
    shell,
    cwd,
    process_environment=environment,
    options~,
  ) catch {
    error => raise Executor(error)
  }
}

///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] invocation_values_async(
  process : P,
  host : H,
  compilation : @semantic.Compilation,
  invocation : @invocation.Invocation,
  global : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
) -> Array[@value.Value] raise ApplicationError {
  guard compilation.recipe(invocation.recipe()) is Some(recipe) else {
    raise Query("recipe `\{invocation.recipe()}` does not exist")
  }
  let scope = @evaluator.Environment::child(global)
  let result : Array[@value.Value] = []
  let effect_shell = @evaluator.EffectShell::new(
    shell.program(),
    shell.arguments().to_owned(),
  )
  for index, parameter in recipe.parameters() {
    let elements = invocation.arguments()[index].elements()
    if parameter.variadic() {
      for element in elements {
        result.push(String(element))
      }
      scope.set(
        parameter.name(),
        List(elements.map(fn(element) { String(element) })),
      )
    } else {
      let value = match elements.length() {
        0 =>
          match parameter.default_value() {
            Some(expression) =>
              @evaluator.evaluate_with_async_effects(
                process,
                host,
                expression,
                context,
                effect_shell,
                environment=scope,
              ) catch {
                error => raise Evaluation(error)
              }
            None => String("")
          }
        1 => String(elements[0])
        _ => List(elements.map(fn(element) { String(element) }))
      }
      result.push(value)
      scope.set(parameter.name(), value)
    }
  }
  result
}

///|
/// Async application boundary. All parsing, semantic work, invocation
/// validation, and effectful interpolation are complete before runtime steps
/// are handed to the process adapter.
pub async fn[
  F : @host.HostFs,
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] plan_run_command_async(
  filesystem : F,
  effects : H,
  process : P,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @executor.ExecutionPlan raise ApplicationError {
  if arguments.command() != RunCommand {
    raise UnsupportedCommand("execution planning for non-run command")
  }
  let (loaded, directories) = load_input_with_directories(
    filesystem, arguments, context,
  )
  let compilation = compile_loaded(loaded)
  let overrides = variable_overrides(compilation, arguments)
  let invocations = @invocation.parse_invocations(
    compilation,
    arguments.positional(),
    overrides~,
  ) catch {
    error => raise Invocation(error)
  }
  let cwd = directories.recipe_directory(
    module_no_cd=compilation.settings().bool("no-cd"),
  ) catch {
    error => raise WorkingDirectory(error)
  }
  let context = @evaluator.EvaluationContext::new(
    cwd~,
    color_mode=arguments.value("color").unwrap_or("auto"),
  )
  let global = @evaluator.evaluate_compilation_with_async_effects(
    process,
    effects,
    compilation,
    context,
    @evaluator.EffectShell::new("sh", ["-cu"]),
    overrides~,
  ) catch {
    error => raise Evaluation(error)
  }
  let module_setting = evaluated_string_setting(
    compilation, global, "working-directory",
  )
  let cwd = directories.recipe_directory(
    module_setting~,
    module_no_cd=compilation.settings().bool("no-cd"),
  ) catch {
    error => raise WorkingDirectory(error)
  }
  let context = @evaluator.EvaluationContext::new(
    cwd~,
    color_mode=arguments.value("color").unwrap_or("auto"),
  )
  let shell = selected_shell(compilation, global, arguments, cwd.flavor())
  let requests : Array[@executor.RecipeRequest] = []
  for invocation in invocations {
    requests.push(
      @executor.RecipeRequest::new(
        invocation.recipe(),
        arguments=invocation_values_async(
          process, effects, compilation, invocation, global, context, shell,
        ),
      ),
    )
  }
  let environment = process_environment(effects, global, cwd.flavor())
  let environment = compose_dotenv_environment(
    filesystem, compilation, arguments, global, cwd, environment,
  )
  let platform = @host.HostPlatform::platform_info(effects) catch {
    error => raise Host(error)
  }
  let script_interpreter = evaluated_shell_setting(
    compilation, global, "script-interpreter",
  ).unwrap_or(shell)
  let setting_tempdir = evaluated_string_setting(compilation, global, "tempdir")
  let temporary = @environment.resolve_temporary_directory(
    cwd,
    cli_tempdir=arguments.value("tempdir"),
    setting_tempdir~,
  ) catch {
    InvalidOverridePath(path~) => raise Environment(InvalidOverridePath(path~))
    EmptyShell => raise Environment(EmptyShell)
    Path(error) => raise Environment(Path(error))
  }
  let configuration = @executor.ScriptConfiguration::new(
    script_interpreter,
    temporary.directory().unwrap_or(cwd),
    platform,
  )
  let timestamp = selected_timestamp(effects, arguments)
  let command_color = selected_command_color(effects, arguments)
  let options = execution_options(arguments, timestamp, command_color)
  let cache_directory = cache_directory(directories.project_directory())
  @executor.plan_recipe_graph_async(
    process,
    effects,
    compilation,
    requests,
    global,
    context,
    shell,
    cwd,
    configuration,
    process_environment=environment,
    options~,
    cache_directory~,
  ) catch {
    error => raise Executor(error)
  }
}
