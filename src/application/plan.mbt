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
      let value = @evaluator.evaluate_with_context(
        expression,
        @evaluator.EvaluationContext::new(lists=true),
        environment=global,
      ) catch {
        error => raise Evaluation(error)
      }
      let parts = value.elements()
      guard parts.get(0) is Some(program) else {
        raise Semantic(
          EmptySetting(
            name~,
            span=compilation.settings().span(name).unwrap_or(expression.span()),
          ),
        )
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
      let value = @evaluator.evaluate_with_context(
        expression,
        @evaluator.EvaluationContext::new(
          lists=compilation.settings().bool("lists"),
        ),
        environment=global,
      ) catch {
        error => raise Evaluation(error)
      }
      match value {
        String(value) => Some(value)
        value =>
          raise Semantic(
            ListsFeature(
              message=value.kind() +
                " value " +
                value.display() +
                " assigned to `" +
                name +
                "` setting",
              span=compilation
                .settings()
                .span(name)
                .unwrap_or(expression.span()),
            ),
          )
      }
    }
    _ => None
  }
}

///|
fn evaluated_const_string_setting(
  compilation : @semantic.Compilation,
  parent : @evaluator.Environment,
  overrides : ArrayView[(String, String)],
  name : String,
) -> String? raise ApplicationError {
  match compilation.settings().get(name) {
    Some(Text(value)) => Some(value)
    Some(Expression(expression)) => {
      let environment = @evaluator.LazyEnvironment::new(
        compilation,
        environment=@evaluator.Environment::child(parent),
      )
      environment.apply_overrides(overrides) catch {
        error => raise Evaluation(error)
      }
      let value = environment.evaluate_expression(expression) catch {
        error => raise Evaluation(error)
      }
      match value {
        String(value) => Some(value)
        value =>
          raise Semantic(
            ListsFeature(
              message=value.kind() +
                " value " +
                value.display() +
                " assigned to `" +
                name +
                "` setting",
              span=compilation
                .settings()
                .span(name)
                .unwrap_or(expression.span()),
            ),
          )
      }
    }
    _ => None
  }
}

///|
fn evaluated_const_shell_setting(
  compilation : @semantic.Compilation,
  parent : @evaluator.Environment,
  overrides : ArrayView[(String, String)],
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
      let environment = @evaluator.LazyEnvironment::new(
        compilation,
        environment=@evaluator.Environment::child(parent),
      )
      environment.apply_overrides(overrides) catch {
        error => raise Evaluation(error)
      }
      let value = environment.evaluate_expression(expression) catch {
        error => raise Evaluation(error)
      }
      let parts = value.elements()
      guard parts.get(0) is Some(program) else {
        raise Semantic(
          EmptySetting(
            name~,
            span=compilation.settings().span(name).unwrap_or(expression.span()),
          ),
        )
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
fn validate_no_recipe_variable_cycles(
  project : @semantic.ProjectCompilation,
) -> Unit raise ApplicationError {
  let compilation = project.root()
  guard compilation.recipe_names().is_empty() else { return }
  let environment = @evaluator.LazyEnvironment::new(compilation)
  for name in compilation.variable_names() {
    try ignore(environment.resolve(name)) catch {
      VariableCycle(..) as error => raise Evaluation(error)
      _ => ()
    } noraise {
      _ => ()
    }
  }
}

///|
fn validate_project_const_settings(
  project : @semantic.ProjectCompilation,
  arguments : @cli.CliArguments,
  flavor : @path.PathFlavor,
) -> Unit raise ApplicationError {
  fn const_setting_error(
    expression : @syntax.Expression,
    error : @evaluator.EvaluationError,
  ) -> ApplicationError {
    match error {
      EffectRequired(_) =>
        match expression {
          Variable(name~, span~) => Semantic(NonConstVariable(name~, span~))
          Backtick(literal) =>
            Semantic(ConstContext(kind="backticks", span=literal.span()))
          Call(name~, span~, ..) => {
            let name_span = @source.Span::new(
              span.source_id(),
              span.start_byte(),
              span.start_byte() + name.length(),
            ) catch {
              _ => span
            }
            Semantic(ConstContext(kind="functions", span=name_span))
          }
          _ => Evaluation(error)
        }
      _ => Evaluation(error)
    }
  }
  for path in project.module_paths() {
    let compilation = project.module_compilation(path).unwrap()
    let seed = @evaluator.Environment::new()
    @evaluator.install_constants(seed, flavor)
    let environment = @evaluator.LazyEnvironment::new(
      compilation,
      environment=seed,
    )
    let overrides = project_variable_overrides(project, path, arguments)
    environment.apply_overrides(overrides) catch {
      error => raise Evaluation(error)
    }
    for name in compilation.settings().names() {
      match compilation.settings().get(name) {
        Some(Expression(expression)) => {
          let value = environment.evaluate_expression(expression) catch {
            error => raise const_setting_error(expression, error)
          }
          if ["shell", "script-interpreter", "windows-shell"].contains(name) &&
            value.elements().is_empty() {
            raise Semantic(
              EmptySetting(
                name~,
                span=compilation
                  .settings()
                  .span(name)
                  .unwrap_or(expression.span()),
              ),
            )
          }
        }
        _ => ()
      }
    }
  }
}

///|
fn selected_shell_before_globals(
  compilation : @semantic.Compilation,
  parent : @evaluator.Environment,
  overrides : ArrayView[(String, String)],
  arguments : @cli.CliArguments,
  flavor : @path.PathFlavor,
) -> @environment.ShellConfiguration raise ApplicationError {
  let info = if flavor == Windows {
    @host.PlatformInfo::new(Windows, "unknown", Windows)
  } else {
    @host.PlatformInfo::new(Other("unix"), "unknown", Unix)
  }
  let platform = @environment.PlatformConfiguration::new(info)
  let setting_shell = evaluated_const_shell_setting(
    compilation, parent, overrides, "shell",
  )
  let windows_shell = evaluated_const_shell_setting(
    compilation, parent, overrides, "windows-shell",
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
fn[T : @host.HostTerminal] selected_color_active(
  effects : T,
  arguments : @cli.CliArguments,
) -> Bool raise ApplicationError {
  let mode = arguments.value("color").unwrap_or("auto")
  match mode {
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
}

///|
fn selected_command_color(
  arguments : @cli.CliArguments,
  color_active : Bool,
) -> @executor.CommandColor? raise ApplicationError {
  if !color_active || arguments.flag("no-highlight") {
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
  color_enabled : Bool,
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
  .with_no_dependencies(arguments.flag("no-deps"))
  .with_explain(arguments.flag("explain"))
  .with_color_enabled(color_enabled)
  .with_verbosity(arguments.count("verbose"))
}

///|
fn cache_directory(
  project : @path.PathValue,
) -> @path.PathValue raise ApplicationError {
  let relative = @path.PathValue::new(".justcache", project.flavor()) catch {
    error => raise Path(error)
  }
  project.join(relative) catch {
    error => raise Path(error)
  }
}

///|
/// The synchronous executor is safe for a deliberately narrow dry-run shape.
/// Keep this predicate conservative: an unsupported expression must retain the
/// async evaluator's effect and diagnostic behavior rather than being retried
/// after a synchronous failure.
fn expression_uses_effects(expression : @syntax.Expression) -> Bool {
  match expression {
    String(_) | Boolean(_) | Variable(_) => false
    Backtick(_) | Call(_) => true
    List(elements~, ..) => elements.any(expression_uses_effects)
    Parenthesized(expression~, ..) => expression_uses_effects(expression)
    Unary(operand~, ..) => expression_uses_effects(operand)
    Binary(lhs~, rhs~, ..) =>
      expression_uses_effects(lhs) || expression_uses_effects(rhs)
    Conditional(condition~, then_branch~, else_branch~, ..) =>
      expression_uses_effects(condition) ||
      expression_uses_effects(then_branch) ||
      else_branch.map(expression_uses_effects).unwrap_or(false)
    Format(parts~, ..) =>
      parts.any(fn(part) { expression_uses_effects(part.expression()) })
  }
}

///|
fn recipe_has_shebang_for_sync_check(recipe : @syntax.Recipe) -> Bool {
  guard recipe.lines().get(0) is Some(line) else { return false }
  guard line.fragments().get(0) is Some(Text(text~, ..)) else { return false }
  text.has_prefix("#!")
}

///|
fn compilation_supports_sync_dry_run(
  compilation : @semantic.Compilation,
) -> Bool {
  let settings = compilation.settings()
  if settings.bool("guards") || settings.bool("default-script") {
    return false
  }
  let mut has_recipe = false
  for recipe_name in compilation.recipe_names() {
    guard compilation.recipe(recipe_name) is Some(recipe) else { return false }
    has_recipe = true
    if !recipe.attributes().is_empty() ||
      recipe_has_shebang_for_sync_check(recipe) {
      return false
    }
    for parameter in recipe.parameters() {
      match parameter.default_value() {
        Some(expression) if expression_uses_effects(expression) => return false
        _ => ()
      }
    }
    for dependency in recipe.dependencies() {
      for expression in dependency.arguments() {
        if expression_uses_effects(expression) {
          return false
        }
      }
    }
    for dependency in recipe.subsequent_dependencies() {
      for expression in dependency.arguments() {
        if expression_uses_effects(expression) {
          return false
        }
      }
    }
    for line in recipe.lines() {
      for fragment in line.fragments() {
        match fragment {
          Interpolation(expression~, ..) if expression_uses_effects(expression) =>
            return false
          _ => ()
        }
      }
    }
  }
  has_recipe
}

///|
fn project_supports_sync_dry_run(
  project : @semantic.ProjectCompilation,
) -> Bool {
  if project.module_paths().length() != 1 {
    return false
  }
  guard project.module_paths().get(0) is Some(path) else { return false }
  guard project.module_compilation(path) is Some(compilation) else {
    return false
  }
  compilation_supports_sync_dry_run(compilation)
}

///|
fn project_supports_pure_sync_globals(
  project : @semantic.ProjectCompilation,
  arguments : @cli.CliArguments,
) -> Bool {
  guard project.module_paths().length() == 1 else { return false }
  guard project.module_paths().get(0) is Some(path) else { return false }
  guard project.module_compilation(path) is Some(compilation) else {
    return false
  }
  if !compilation.function_names().is_empty() {
    return false
  }
  for
    name in [
      "dotenv-command", "dotenv-filename", "dotenv-load", "dotenv-override", "dotenv-path",
      "dotenv-required",
    ] {
    if compilation.settings().has(name) {
      return false
    }
  }
  if !arguments.values("dotenv-command").is_empty() ||
    !arguments.values("dotenv-filename").is_empty() ||
    !arguments.values("dotenv-path").is_empty() {
    return false
  }
  for name in compilation.variable_names() {
    guard compilation.variable(name) is Some(assignment) else { return false }
    if expression_uses_effects(assignment.value()) {
      return false
    }
  }
  for name in compilation.settings().names() {
    match compilation.settings().get(name) {
      Some(Expression(expression)) if expression_uses_effects(expression) =>
        return false
      _ => ()
    }
  }
  true
}

///|
fn project_module_base(
  project : @semantic.ProjectCompilation,
  directories : @workdir.WorkingDirectoryModel,
  path : @modulepath.ModulePath,
) -> @path.PathValue raise ApplicationError {
  if path.is_root() {
    directories.module_directory()
  } else {
    match project.directory(path) {
      Some(directory) => directory
      None => raise Query("unknown module `" + path.as_string() + "`")
    }
  }
}

///|
fn project_module_cwd(
  project : @semantic.ProjectCompilation,
  directories : @workdir.WorkingDirectoryModel,
  path : @modulepath.ModulePath,
  setting : String?,
  no_cd : Bool,
) -> @path.PathValue raise ApplicationError {
  if no_cd {
    return directories.invocation_directory()
  }
  let base = project_module_base(project, directories, path)
  match setting {
    None => base
    Some(value) => {
      let relative = @path.PathValue::new(value, base.flavor()) catch {
        error => raise Path(error)
      }
      base.join(relative) catch {
        error => raise Path(error)
      }
    }
  }
}

///|
fn project_evaluation_context(
  project : @semantic.ProjectCompilation,
  path : @modulepath.ModulePath,
  cwd : @path.PathValue,
  directories : @workdir.WorkingDirectoryModel,
  arguments : @cli.CliArguments,
  invocation_directory : @path.PathValue,
  environment? : Array[(String, String)],
  platform? : @host.PlatformInfo,
) -> @evaluator.EvaluationContext {
  fn environment_value(
    entries : ArrayView[(String, String)],
    name : String,
  ) -> String? {
    for entry in entries {
      if entry.0 == name {
        return Some(entry.1)
      }
    }
    None
  }
  fn environment_path(
    entries : ArrayView[(String, String)],
    name : String,
    flavor : @path.PathFlavor,
  ) -> @path.PathValue? {
    match environment_value(entries, name) {
      Some(value) if !value.is_empty() =>
        Some(@path.PathValue::new(value, flavor)) catch {
          _ => None
        }
      _ => None
    }
  }
  fn child_path(parent : @path.PathValue?, child : String) -> @path.PathValue? {
    guard parent is Some(parent) else { return None }
    let relative = @path.PathValue::new(child, parent.flavor()) catch {
      _ => return None
    }
    Some(parent.join(relative)) catch {
      _ => None
    }
  }
  fn prefer_path(
    primary : @path.PathValue?,
    fallback : @path.PathValue?,
  ) -> @path.PathValue? {
    match primary {
      Some(value) => Some(value)
      None => fallback
    }
  }
  let entries = environment.unwrap_or([])
  let home = environment_path(entries, "HOME", cwd.flavor())
  let windows = platform
    .map(fn(value) { value.operating_system() == Windows })
    .unwrap_or(false)
  let macos_home = home
    .map(fn(path) { path.as_string().has_prefix("/Users/") })
    .unwrap_or(false) ||
    environment_value(entries, "__CF_USER_TEXT_ENCODING") is Some(_)
  let application_support = child_path(home, "Library/Application Support")
  let windows_appdata = environment_path(entries, "APPDATA", cwd.flavor())
  let windows_local_appdata = environment_path(
    entries,
    "LOCALAPPDATA",
    cwd.flavor(),
  )
  let config = prefer_path(
    if windows {
      windows_appdata
    } else {
      environment_path(entries, "XDG_CONFIG_HOME", cwd.flavor())
    },
    if windows {
      windows_appdata
    } else if macos_home {
      application_support
    } else {
      child_path(home, ".config")
    },
  )
  let data = prefer_path(
    if windows {
      windows_appdata
    } else {
      environment_path(entries, "XDG_DATA_HOME", cwd.flavor())
    },
    if windows {
      windows_local_appdata
    } else if macos_home {
      application_support
    } else {
      child_path(home, ".local/share")
    },
  )
  let cache = prefer_path(
    if windows {
      windows_local_appdata
    } else {
      environment_path(entries, "XDG_CACHE_HOME", cwd.flavor())
    },
    if windows {
      windows_local_appdata
    } else if macos_home {
      child_path(home, "Library/Caches")
    } else {
      child_path(home, ".cache")
    },
  )
  let executable = match platform {
    Some(platform) =>
      match platform.executable() {
        Some(value) =>
          Some(@path.PathValue::new(value, cwd.flavor())) catch {
            _ => None
          }
        None => None
      }
    None => None
  }
  let executable_directory = match platform {
    Some(info) if info.operating_system() == Linux =>
      prefer_path(
        environment_path(entries, "XDG_BIN_HOME", cwd.flavor()),
        child_path(home, ".local/bin"),
      )
    _ => None
  }
  let (pid, num_cpus) = match platform {
    Some(value) => (value.pid(), value.num_cpus())
    None => (None, None)
  }
  let num_jobs = match arguments.value("jobs") {
    Some(value) => Some(@string.parse_int(value[:])) catch { _ => None }
    None => None
  }
  let module_name = if path.is_root() {
    None
  } else {
    path.components().last().map(fn(value) { value })
  }
  @evaluator.EvaluationContext::new(
    cwd~,
    module_name?,
    justfile?=directories.justfile(),
    source_file?=project.source_file(path),
    source_files=project.source_files(path),
    module_file?=project.source_file(path),
    module_path=path.as_string(),
    executable?,
    executable_directory?,
    invocation_directory~,
    invocation_directory_native=directories.invocation_directory(),
    home_directory?=home,
    config_directory?=config,
    config_local_directory?=if windows { windows_local_appdata } else { config },
    data_directory?=data,
    data_local_directory?=if windows { windows_local_appdata } else { data },
    cache_directory?=cache,
    runtime_directory?=environment_path(
      entries,
      "XDG_RUNTIME_DIR",
      cwd.flavor(),
    ),
    pid?,
    num_cpus?,
    num_jobs?,
    color_mode=arguments.value("color").unwrap_or("auto"),
    command_color?=arguments.value("command-color"),
    lists=project.module_compilation(path).unwrap().settings().bool("lists"),
    utc_offset_seconds=0,
    environment?,
    process_environment?=environment,
  )
}

///|
fn windows_drive_path_to_unix(path : @path.PathValue) -> @path.PathValue? {
  let text = path.as_string()
  let characters = text.to_array()
  guard characters.length() >= 3 && characters[1] == ':' else { return None }
  guard characters[2] == '\\' || characters[2] == '/' else { return None }
  let drive = characters[0]
  guard drive.is_ascii_alphabetic() else { return None }
  let lower_drive = (if drive.is_ascii_uppercase() {
    (drive.to_int() + 32).to_char().unwrap()
  } else {
    drive
  }).to_string()
  let rest = text[2:].to_owned().replace_all(old="\\", new="/")
  Some(
    @path.PathValue::new("/" + lower_drive + rest, Unix) catch {
      _ => return None
    },
  )
}

///|
async fn[P : @host.HostAsyncProcess] shell_invocation_directory(
  process : P,
  directories : @workdir.WorkingDirectoryModel,
  arguments : @cli.CliArguments,
  platform : @host.PlatformInfo,
) -> @path.PathValue noraise {
  let native = directories.invocation_directory()
  if platform.operating_system() != Windows {
    return native
  }
  // cygpath is only needed for UNC/MSYS mount paths. Ordinary drive paths
  // have a deterministic conversion that avoids a helper process during
  // every dry-run plan while preserving the Unix-facing builtin value.
  match windows_drive_path_to_unix(native) {
    Some(value) => return value
    None => ()
  }
  let program = arguments.value("cygpath").unwrap_or("cygpath")
  let spec = @host.CommandSpec::new(program, ["--unix", native.as_string()]) catch {
    _ => return native
  }
  spec.set_cwd(native)
  spec.set_stdout(Capture)
  spec.set_stderr(Discard)
  let output = try
    @host.HostAsyncProcess::run_process_async(process, spec)
  catch {
    _ => return native
  } noraise {
    value => value
  }
  guard output.exit_code() == Some(0) else { return native }
  let text = try @utf8.decode(output.stdout()) catch {
    _ => return native
  } noraise {
    value => value.trim_end().to_owned()
  }
  if text.is_empty() {
    return native
  }
  @path.PathValue::new(text, Unix) catch {
    _ => native
  }
}

///|
fn semantic_target_platform(
  platform : @host.PlatformInfo,
) -> @semantic.TargetPlatform {
  match platform.operating_system() {
    Linux => @semantic.TargetPlatform::new(Linux, true)
    Macos => @semantic.TargetPlatform::new(Macos, true)
    Windows => @semantic.TargetPlatform::new(Windows, false)
    Other(name) => @semantic.TargetPlatform::new(Other(name), false)
  }
}

///|
fn evaluate_project_globals(
  project : @semantic.ProjectCompilation,
  arguments : @cli.CliArguments,
  flavor? : @path.PathFlavor,
) -> Map[@modulepath.ModulePath, @evaluator.Environment] raise ApplicationError {
  validate_project_variable_overrides(project, arguments)
  let globals : Map[@modulepath.ModulePath, @evaluator.Environment] = Map([])
  for path in project.module_paths() {
    let seed = match path.parent() {
      Some(parent) =>
        match globals.get(parent) {
          Some(environment) => @evaluator.Environment::module_scope(environment)
          None => @evaluator.Environment::new()
        }
      None => @evaluator.Environment::new()
    }
    let compilation = project.module_compilation(path).unwrap()
    @evaluator.install_constants(
      seed,
      flavor.unwrap_or(
        project
        .source_file(path)
        .map(fn(value) { value.flavor() })
        .unwrap_or(Unix),
      ),
    )
    for name in compilation.unexports() {
      seed.remove(name)
    }
    let overrides = project_variable_overrides(project, path, arguments)
    let global = @evaluator.evaluate_compilation(
      compilation,
      environment=seed,
      overrides~,
    ) catch {
      error => raise Evaluation(error)
    }
    globals[path] = global
  }
  globals
}

///|
fn[H : @host.HostClock] selected_timestamp(
  effects : H,
  arguments : @cli.CliArguments,
) -> String? raise ApplicationError {
  if !arguments.flag("timestamp") {
    return None
  }
  let format = arguments.value("timestamp-format").unwrap_or("%H:%M:%S")
  if !@executor.valid_timestamp_format(format) {
    raise Query(
      "failed to parse time format string `\{format}`: bad or unsupported format string",
    )
  }
  let millis = @host.HostClock::now_millis(effects) catch {
    error => raise Host(error)
  }
  Some(@executor.format_timestamp(millis, format))
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
      let elements = if elements.is_empty() {
        match parameter.default_value() {
          Some(expression) =>
            (@evaluator.evaluate(expression, environment=scope) catch {
              error => raise Evaluation(error)
            }).elements()
          None => elements.map(fn(element) { element })
        }
      } else {
        elements.map(fn(element) { element })
      }
      for element in elements {
        result.push(String(element))
      }
      scope.set(
        parameter.name(),
        List(elements.map(fn(element) { String(element) })),
      )
    } else if invocation.arguments()[index].list() {
      let value : @value.Value = List(
        elements.map(fn(element) { String(element) }),
      )
      result.push(value)
      scope.set(parameter.name(), value)
    } else {
      let value : @value.Value = match elements.length() {
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
fn process_environment(
  entries : ArrayView[(String, String)],
  global : @evaluator.Environment,
  flavor : @path.PathFlavor,
  unexports? : ArrayView[String] = [],
) -> Array[(String, String)] {
  let mode : @environment.EnvNameMode = if flavor == Windows {
    AsciiInsensitive
  } else {
    Sensitive
  }
  let table = @environment.EnvTable::from_entries(entries, name_mode=mode)
  for name in unexports {
    table.remove(name)
  }
  for name in global.names() {
    if global.is_exported(name) {
      match global.get(name) {
        Some(value) =>
          if value.elements().is_empty() {
            table.remove(name)
          } else {
            table.set(name, value.to_string())
          }
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
      let evaluated = @evaluator.evaluate_with_context(
        expression,
        @evaluator.EvaluationContext::new(
          lists=compilation.settings().bool("lists"),
        ),
        environment=global,
      ) catch {
        error => raise Evaluation(error)
      }
      evaluated.elements()
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
fn dotenv_command_specs(
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
  global : @evaluator.Environment,
  shell : @environment.ShellConfiguration,
  ambient : ArrayView[(String, String)],
  root_module : Bool,
) -> Array[@host.CommandSpec] raise ApplicationError {
  let from_cli = root_module && !arguments.values("dotenv-command").is_empty()
  let commands = if from_cli {
    arguments.values("dotenv-command").to_owned()
  } else {
    setting_string_values(compilation, global, "dotenv-command")
  }
  if !from_cli && commands.length() > 1 && !compilation.settings().bool("lists") {
    raise Dotenv(ArgumentsRequireLists)
  }
  let result : Array[@host.CommandSpec] = []
  for command in commands {
    let shell_arguments = shell.arguments().to_owned()
    shell_arguments.push(command)
    let spec = @host.CommandSpec::new(shell.program(), shell_arguments) catch {
      error => raise Host(error)
    }
    for entry in ambient {
      spec.add_environment(entry.0, entry.1) catch {
        error => raise Host(error)
      }
    }
    spec.set_inherit_stdin(true)
    spec.set_stdout(Capture)
    spec.set_stderr(
      if arguments.flag("quiet") || compilation.settings().bool("quiet") {
        Discard
      } else {
        Inherit
      },
    )
    result.push(spec)
  }
  result
}

///|
async fn[P : @host.HostAsyncProcess] load_dotenv_commands_async(
  process : P,
  cwd : @path.PathValue,
  ambient : @environment.EnvTable,
  commands : ArrayView[@host.CommandSpec],
  override_environment : Bool,
  dry_run : Bool,
) -> @environment.EnvTable raise ApplicationError {
  let result = @environment.EnvTable::new(name_mode=ambient.name_mode())
  if dry_run {
    return result
  }
  for index, command in commands {
    let command_text = command.arguments().last().unwrap_or("")
    command.set_cwd(cwd)
    let output = @host.HostAsyncProcess::run_process_async(process, command) catch {
      _ => raise Dotenv(CommandUnavailable(index=index + 1))
    }
    match output.exit_code() {
      Some(0) => ()
      Some(code) => raise DotenvCommand(command=command_text, exit_code=code)
      None => raise Dotenv(CommandUnavailable(index=index + 1))
    }
    let text = @utf8.decode(output.stdout()) catch {
      _ => raise Dotenv(Parse(line=1, column=1))
    }
    let loaded = @environment.parse_dotenv(text, ambient~) catch {
      error => raise Dotenv(error)
    }
    for entry in loaded.entries() {
      if override_environment || !ambient.contains(entry.0) {
        result.set(entry.0, entry.1)
      }
    }
  }
  result
}

///|
fn dotenv_runtime_path(
  base : @path.PathValue,
  value : String,
) -> @path.PathValue raise ApplicationError {
  let child = @path.PathValue::new(value, base.flavor()) catch {
    _ => raise Dotenv(InvalidPath)
  }
  base.join(child) catch {
    _ => raise Dotenv(InvalidPath)
  }
}

///|
async fn[F : @host.HostFs + @host.HostSourceReader] read_dotenv_runtime_file(
  filesystem : F,
  path : @path.PathValue,
  ambient : @environment.EnvTable,
) -> @environment.EnvTable? raise ApplicationError {
  let metadata = @host.HostFs::metadata(filesystem, path) catch {
    _ => raise Dotenv(SourceAccess)
  }
  if metadata.is_directory() {
    return None
  }
  let bytes = @host.HostSourceReader::read_source(
    filesystem,
    path,
    @lexer.LexerLimits::default().max_source_bytes(),
  ) catch {
    _ => raise Dotenv(SourceAccess)
  }
  let text = @utf8.decode(bytes) catch { _ => raise Dotenv(InvalidUtf8(path~)) }
  Some(
    @environment.parse_dotenv(text, ambient~) catch {
      Parse(line~, column~) => raise Dotenv(ParseFile(path~, line~, column~))
      error => raise Dotenv(error)
    },
  )
}

///|
async fn[F : @host.HostFs + @host.HostSourceReader] load_dotenv_files_for_runtime(
  filesystem : F,
  portable_runtime : Bool,
  cwd : @path.PathValue,
  ambient : @environment.EnvTable,
  load : Bool,
  override_environment : Bool,
  required : Bool,
  lists : Bool,
  filenames : Array[String],
  paths : Array[String],
) -> @environment.EnvTable raise ApplicationError {
  if !portable_runtime {
    return @environment.load_dotenv_files(
      filesystem,
      cwd,
      ambient,
      @environment.DotenvOptions::new(
        load~,
        override_environment~,
        required~,
        lists~,
        filenames~,
        paths~,
      ),
    ) catch {
      error => raise Dotenv(error)
    }
  }
  if !lists && (filenames.length() > 1 || paths.length() > 1) {
    raise Dotenv(ArgumentsRequireLists)
  }
  if !load && !override_environment && filenames.is_empty() && paths.is_empty() {
    return @environment.EnvTable::new(name_mode=ambient.name_mode())
  }
  let result = @environment.EnvTable::new(name_mode=ambient.name_mode())
  let mut found = false
  fn merge(
    result : @environment.EnvTable,
    loaded : @environment.EnvTable,
    ambient : @environment.EnvTable,
    override_environment : Bool,
  ) -> Unit {
    for entry in loaded.entries() {
      if override_environment || !ambient.contains(entry.0) {
        result.set(entry.0, entry.1)
      }
    }
  }
  for value in paths {
    let path = dotenv_runtime_path(cwd, value)
    let exists = @host.HostFs::file_exists(filesystem, path) catch {
      _ => raise Dotenv(SourceAccess)
    }
    if exists {
      match read_dotenv_runtime_file(filesystem, path, ambient) {
        Some(loaded) => {
          merge(result, loaded, ambient, override_environment)
          found = true
        }
        None => ()
      }
    }
  }
  if found {
    return result
  }
  let names = if filenames.is_empty() { [".env"] } else { filenames }
  let mut directory = Some(cwd)
  while directory is Some(current) {
    for filename in names {
      let path = dotenv_runtime_path(current, filename)
      let exists = @host.HostFs::file_exists(filesystem, path) catch {
        _ => raise Dotenv(SourceAccess)
      }
      if exists {
        match read_dotenv_runtime_file(filesystem, path, ambient) {
          Some(loaded) => {
            merge(result, loaded, ambient, override_environment)
            found = true
          }
          None => ()
        }
      }
    }
    if found {
      return result
    }
    directory = current.parent()
  }
  if required {
    raise Dotenv(Required)
  }
  result
}

///|
async fn[F : @host.HostFs + @host.HostSourceReader, P : @host.HostAsyncProcess] compose_dotenv_environment_async(
  filesystem : F,
  process : P,
  portable_runtime : Bool,
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
  global : @evaluator.Environment,
  cwd : @path.PathValue,
  ambient_entries : ArrayView[(String, String)],
  shell : @environment.ShellConfiguration,
  root_module : Bool,
) -> (Array[(String, String)], Array[(String, String)]) raise ApplicationError {
  let mode : @environment.EnvNameMode = if cwd.flavor() == Windows {
    AsciiInsensitive
  } else {
    Sensitive
  }
  let ambient = @environment.EnvTable::from_entries(
    ambient_entries,
    name_mode=mode,
  )
  let commands = dotenv_command_specs(
    compilation, arguments, global, shell, ambient_entries, root_module,
  )
  let dotenv = if commands.is_empty() {
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
    load_dotenv_files_for_runtime(
      filesystem,
      portable_runtime,
      cwd,
      ambient,
      load,
      compilation.settings().bool("dotenv-override"),
      compilation.settings().bool("dotenv-required"),
      compilation.settings().bool("lists"),
      filenames,
      paths,
    )
  } else {
    load_dotenv_commands_async(
      process,
      cwd,
      ambient,
      commands,
      compilation.settings().bool("dotenv-override"),
      arguments.flag("dry-run"),
    )
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
  (result, dotenv.entries())
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
  let loading_environment = @host.HostEnv::env_entries(environment_host) catch {
    error => raise Host(error)
  }
  let (graph, directories) = load_graph_input_with_directories(
    host,
    arguments,
    context,
    environment=loading_environment,
  )
  let project = compile_loaded_graph(
    graph,
    allow_unstable=arguments.flag("unstable"),
  )
  let globals = evaluate_project_globals(project, arguments)
  let invocations = @invocation.parse_project_invocations_in_environments(
    project,
    arguments.positional(),
    globals,
    allow_missing=arguments.flag("allow-missing"),
  ) catch {
    error => raise Invocation(error)
  }
  if arguments.flag("one") && invocations.length() != 1 {
    raise Query(
      "expected 1 command-line recipe invocation but found " +
      invocations.length().to_string(),
    )
  }
  let color_enabled = selected_color_active(environment_host, arguments)
  let command_color = selected_command_color(arguments, color_enabled)
  let options = execution_options(arguments, None, command_color, color_enabled)
  let plans : Array[@executor.ExecutionPlan] = []
  for project_invocation in invocations {
    let path = project_invocation.module_path()
    let invocation = project_invocation.invocation()
    let compilation = project.module_compilation(path).unwrap()
    let global = globals[path]
    let module_setting = evaluated_string_setting(
      compilation, global, "working-directory",
    )
    let cwd = project_module_cwd(
      project,
      directories,
      path,
      module_setting,
      compilation.settings().bool("no-cd"),
    )
    let shell = selected_shell(compilation, global, arguments, cwd.flavor())
    let environment = process_environment(
      loading_environment,
      global,
      cwd.flavor(),
      unexports=compilation.unexports(),
    )
    let values = invocation_values(compilation, invocation, global)
    plans.push(
      @executor.plan_recipe_graph(
        compilation,
        [@executor.RecipeRequest::new(invocation.recipe(), arguments=values)],
        global,
        shell,
        cwd,
        process_environment=environment,
        options=options.with_echo_quiet(
          options.echo_quiet() || compilation.settings().bool("quiet"),
        ),
      ) catch {
        error => raise Executor(error)
      },
    )
  }
  @executor.combine_execution_plans(plans)
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
    let raw_elements = invocation.arguments()[index].elements()
    let elements : Array[String] = []
    let value_expression = @invocation.recipe_argument_value_expression(
      compilation,
      invocation.recipe(),
      parameter.name(),
    ) catch {
      error => raise Invocation(error)
    }
    match value_expression {
      Some(expression) if !raw_elements.is_empty() =>
        for _ in raw_elements {
          let value = @evaluator.evaluate_with_async_effects(
            process,
            host,
            expression,
            context,
            effect_shell,
            environment=scope,
          ) catch {
            error => raise Evaluation(error)
          }
          elements.append(value.elements())
        }
      _ => elements.append(raw_elements)
    }
    if parameter.variadic() {
      let elements = if elements.is_empty() {
        match parameter.default_value() {
          Some(expression) =>
            (@evaluator.evaluate_with_async_effects(
              process,
              host,
              expression,
              context,
              effect_shell,
              environment=scope,
            ) catch {
              error => raise Evaluation(error)
            }).elements()
          None => elements.map(fn(element) { element })
        }
      } else {
        elements.map(fn(element) { element })
      }
      for element in elements {
        result.push(String(element))
      }
      scope.set(
        parameter.name(),
        List(elements.map(fn(element) { String(element) })),
      )
    } else if invocation.arguments()[index].list() {
      let value : @value.Value = List(
        elements.map(fn(element) { String(element) }),
      )
      result.push(value)
      scope.set(parameter.name(), value)
    } else {
      let value : @value.Value = match elements.length() {
        // Preserve an empty argument as a default-value sentinel. The
        // executor evaluates the default after recipe `[env]` attributes have
        // been applied to the effect process context.
        0 => List([])
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
async fn[
  F : @host.HostFs + @host.HostSourceReader,
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] evaluate_project_globals_async(
  filesystem : F,
  process : P,
  effects : H,
  project : @semantic.ProjectCompilation,
  directories : @workdir.WorkingDirectoryModel,
  arguments : @cli.CliArguments,
  platform : @host.PlatformInfo,
  loading_environment : ArrayView[(String, String)],
  invocation_directory : @path.PathValue,
  targets? : ArrayView[(@modulepath.ModulePath, String)],
  evaluation_target? : (@modulepath.ModulePath, String?),
) -> (
  Map[@modulepath.ModulePath, @evaluator.Environment],
  Map[@modulepath.ModulePath, Array[(String, String)]],
) raise ApplicationError {
  validate_project_variable_overrides(project, arguments)
  let globals : Map[@modulepath.ModulePath, @evaluator.Environment] = Map([])
  let dotenv_by_module : Map[@modulepath.ModulePath, Array[(String, String)]] = Map([],
  )
  for path in project.module_paths() {
    let seed = match path.parent() {
      Some(parent) =>
        match globals.get(parent) {
          Some(environment) => @evaluator.Environment::module_scope(environment)
          None => @evaluator.Environment::new()
        }
      None => @evaluator.Environment::new()
    }
    let compilation = project.module_compilation(path).unwrap()
    @evaluator.install_constants(seed, platform.path_flavor())
    for name in compilation.unexports() {
      seed.remove(name)
    }
    let base = project_module_base(project, directories, path)
    let overrides = project_variable_overrides(project, path, arguments)
    let working_directory = evaluated_const_string_setting(
      compilation, seed, overrides, "working-directory",
    )
    let evaluation_cwd = project_module_cwd(
      project, directories, path, working_directory, false,
    )
    let inherited_dotenv = match path.parent() {
      Some(parent) => dotenv_by_module.get(parent).unwrap_or([])
      None => []
    }
    let ambient = process_environment(
      loading_environment,
      seed,
      base.flavor(),
      unexports=compilation.unexports(),
    )
    let dotenv_shell = selected_shell_before_globals(
      compilation,
      seed,
      overrides,
      arguments,
      base.flavor(),
    )
    let (_, dotenv) = compose_dotenv_environment_async(
      filesystem,
      process,
      platform.portable_runtime(),
      compilation,
      arguments,
      seed,
      base,
      ambient,
      dotenv_shell,
      path.is_root(),
    )
    perf_detail_mark("run.global.dotenv")
    let evaluation_environment = merge_dotenv_entries(
      merge_dotenv_entries(ambient, inherited_dotenv, true),
      dotenv,
      true,
    )
    dotenv_by_module[path] = merge_dotenv_entries(
      inherited_dotenv.copy(),
      dotenv,
      true,
    )
    let evaluation_context = project_evaluation_context(
      project,
      path,
      evaluation_cwd,
      directories,
      arguments,
      invocation_directory,
      environment=evaluation_environment,
      platform~,
    )
    let mut lazy_enabled = compilation.settings().bool("lazy")
    let mut parent = path.parent()
    while parent is Some(parent_path) {
      let parent_compilation = project.module_compilation(parent_path).unwrap()
      if parent_compilation.settings().bool("lazy") {
        lazy_enabled = true
      }
      parent = parent_path.parent()
    }
    let selected_recipes : Array[String] = []
    match targets {
      Some(targets) =>
        for target in targets {
          if target.0 == path {
            selected_recipes.push(target.1)
          }
        }
      None => ()
    }
    let selected = match evaluation_target {
      Some((target_path, target_name)) => {
        let names : Array[String] = if path == target_path {
          match target_name {
            Some(name) => [name]
            None => compilation.variable_names().to_owned()
          }
        } else {
          []
        }
        if target_path.starts_with(path) && path != target_path {
          for name in compilation.variable_names() {
            guard compilation.variable(name) is Some(assignment) else {
              continue
            }
            if assignment.eager() ||
              assignment.exported() ||
              compilation.settings().bool("export") {
              names.push(name)
            }
          }
        }
        names
      }
      None =>
        if lazy_enabled && targets is Some(_) {
          let names = @evaluator.recipe_variable_references(
            compilation, selected_recipes,
          )
          for name in compilation.variable_names() {
            guard compilation.variable(name) is Some(assignment) else {
              continue
            }
            if assignment.eager() ||
              assignment.exported() ||
              compilation.settings().bool("export") {
              if !names.contains(name) {
                names.push(name)
              }
            }
          }
          names
        } else {
          compilation.variable_names().to_owned()
        }
    }
    let global = @evaluator.evaluate_compilation_with_async_effects_selected(
      process,
      effects,
      compilation,
      evaluation_context,
      @evaluator.EffectShell::new(
        dotenv_shell.program(),
        dotenv_shell.arguments().to_owned(),
      ),
      selected,
      environment=seed,
      overrides~,
      quiet=arguments.flag("quiet"),
      dry_run=arguments.flag("dry-run"),
    ) catch {
      error => raise Evaluation(error)
    }
    perf_detail_mark("run.global.evaluate")
    globals[path] = global
  }
  (globals, dotenv_by_module)
}

///|
/// Async application boundary. All parsing, semantic work, invocation
/// validation, and effectful interpolation are complete before runtime steps
/// are handed to the process adapter.
pub async fn[
  F : @host.HostFs + @host.HostSourceReader,
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
  let (arguments, context) = search_prefixed_invocation(arguments, context)
  let platform = @host.HostPlatform::platform_info(effects) catch {
    error => raise Host(error)
  }
  perf_detail_mark("run.platform")
  let loading_environment = @host.HostEnv::env_entries(effects) catch {
    error => raise Host(error)
  }
  perf_detail_mark("run.environment")
  let mut current_context = context
  let mut fallback_depth = 0
  let fallback_stderr = StringBuilder()
  while true {
    let prepared = if fallback_depth == 0 {
      take_prepared_run_project(
        arguments, current_context, platform, loading_environment,
      )
    } else {
      None
    }
    let (graph, directories) = match prepared {
      Some((graph, directories, _)) => {
        perf_detail_mark("run.preloaded")
        (graph, directories)
      }
      None => {
        let value = load_graph_input_with_directories_async(
          filesystem,
          arguments,
          current_context,
          platform=semantic_target_platform(platform),
          environment=loading_environment,
        )
        perf_detail_mark("run.load")
        value
      }
    }
    let project = match prepared {
      Some((_, _, project)) => project
      None => {
        let value = compile_loaded_graph(
          graph,
          allow_unstable=arguments.flag("unstable"),
          platform=semantic_target_platform(platform),
        ) catch {
          Semantic(error) if fallback_depth > 0 => {
            for file in graph.files() {
              if file.source().id() == error.span().source_id() {
                raise ContextualSemantic(
                  error~,
                  source=file.source(),
                  cwd=current_context.cwd(),
                )
              }
            }
            raise Semantic(error)
          }
          error => raise error
        }
        perf_detail_mark("run.compile")
        value
      }
    }
    validate_project_const_settings(project, arguments, platform.path_flavor())
    validate_no_recipe_variable_cycles(project)
    validate_project_variable_overrides(project, arguments)
    let targets = try
      @invocation.parse_project_invocation_targets(
        project,
        arguments.positional(),
        allow_missing=arguments.flag("allow-missing"),
      )
    catch {
      UnknownRecipe(_)
      | UnknownRecipeSuggested(_)
      | UnknownSubmodule(_) as missing if project
        .root()
        .settings()
        .bool("fallback") &&
        arguments.value("justfile") is None &&
        arguments.value("working-directory") is None &&
        !arguments.flag("global-justfile") => {
        guard directories.justfile() is Some(justfile) else {
          raise Invocation(missing)
        }
        guard justfile.parent() is Some(directory) else {
          raise Invocation(missing)
        }
        guard directory.parent() is Some(parent) else {
          raise Invocation(missing)
        }
        let options = @loader.SearchOptions::new(
          filename=arguments.value("justfile-name").unwrap_or("justfile"),
          ceiling=ceiling_argument(arguments, current_context.cwd()),
        )
        try @loader.discover(filesystem, parent, options~) catch {
          NoJustfileFound(_) => raise Invocation(missing)
          error => raise Load(error)
        } noraise {
          _ => ()
        }
        current_context = current_context.with_cwd(parent)
        fallback_depth += 1
        if arguments.flag("verbose") {
          fallback_stderr.write_string("Trying ")
          for _ in 0..<fallback_depth {
            fallback_stderr.write_string(
              ".." + platform.path_flavor().separator().to_string(),
            )
          }
          fallback_stderr.write_string("justfile\n")
        }
        continue
      }
      error => raise Invocation(error)
    } noraise {
      value => value
    }
    perf_detail_mark("run.invocations")
    let sync_dry_run = arguments.flag("dry-run") &&
      !arguments.flag("explain") &&
      project_supports_sync_dry_run(project)
    let pure_sync_globals = sync_dry_run &&
      project_supports_pure_sync_globals(project, arguments)
    let invocation_directory = shell_invocation_directory(
      process, directories, arguments, platform,
    )
    let (globals, dotenv_by_module) = if pure_sync_globals {
      let globals = evaluate_project_globals(
        project,
        arguments,
        flavor=platform.path_flavor(),
      )
      let dotenv_by_module : Map[
        @modulepath.ModulePath,
        Array[(String, String)],
      ] = Map([])
      for path in project.module_paths() {
        dotenv_by_module[path] = []
      }
      (globals, dotenv_by_module)
    } else {
      evaluate_project_globals_async(
        filesystem,
        process,
        effects,
        project,
        directories,
        arguments,
        platform,
        loading_environment,
        invocation_directory,
        targets~,
      )
    }
    perf_detail_mark("run.globals")
    let invocations = @invocation.parse_project_invocations_in_environments(
      project,
      arguments.positional(),
      globals,
      allow_missing=arguments.flag("allow-missing"),
      resolve_expressions=false,
    ) catch {
      error => raise Invocation(error)
    }
    if arguments.flag("one") && invocations.length() != 1 {
      raise Query(
        "expected 1 command-line recipe invocation but found " +
        invocations.length().to_string(),
      )
    }
    perf_detail_mark("run.runtime_setup")
    let timestamp = selected_timestamp(effects, arguments)
    let color_enabled = selected_color_active(effects, arguments)
    let command_color = selected_command_color(arguments, color_enabled)
    let options = execution_options(
      arguments, timestamp, command_color, color_enabled,
    )
    let cache_directory = cache_directory(directories.module_directory())
    let runtimes : Array[@executor.ProjectModuleRuntime] = []
    for path in project.module_paths() {
      let compilation = project.module_compilation(path).unwrap()
      let global = globals[path]
      let module_setting = evaluated_string_setting(
        compilation, global, "working-directory",
      )
      let evaluation_cwd = project_module_cwd(
        project, directories, path, module_setting, false,
      )
      let cwd = if compilation.settings().bool("no-cd") {
        directories.invocation_directory()
      } else {
        evaluation_cwd
      }
      let shell = selected_shell(
        compilation,
        global,
        arguments,
        evaluation_cwd.flavor(),
      )
      let environment = process_environment(
        loading_environment,
        global,
        evaluation_cwd.flavor(),
        unexports=compilation.unexports(),
      )
      let environment = merge_dotenv_entries(
        environment,
        dotenv_by_module[path],
        compilation.settings().bool("dotenv-override"),
      )
      let evaluation_context = project_evaluation_context(
        project,
        path,
        evaluation_cwd,
        directories,
        arguments,
        invocation_directory,
        environment~,
        platform~,
      )
      let script_interpreter = evaluated_shell_setting(
        compilation, global, "script-interpreter",
      ).unwrap_or(
        @environment.ShellConfiguration::new("sh", ["-eu"]) catch {
          error => raise Environment(error)
        },
      )
      let setting_tempdir = evaluated_string_setting(
        compilation, global, "tempdir",
      )
      let temporary = @environment.resolve_temporary_directory(
        cwd,
        cli_tempdir=arguments.value("tempdir"),
        setting_tempdir~,
      ) catch {
        InvalidOverridePath(path~) =>
          raise Environment(InvalidOverridePath(path~))
        EmptyShell => raise Environment(EmptyShell)
        Path(error) => raise Environment(Path(error))
      }
      let configuration = @executor.ScriptConfiguration::new(
        script_interpreter,
        temporary.directory().unwrap_or(cwd),
        platform,
      )
      runtimes.push(
        @executor.ProjectModuleRuntime::new(
          path, global, evaluation_context, shell, cwd, environment, configuration,
        ),
      )
    }
    let requests : Array[@executor.ProjectRecipeRequest] = []
    if sync_dry_run {
      let plans : Array[@executor.ExecutionPlan] = []
      for project_invocation in invocations {
        let path = project_invocation.module_path()
        let invocation = project_invocation.invocation()
        let compilation = project.module_compilation(path).unwrap()
        let global = globals[path]
        let mut selected_runtime : @executor.ProjectModuleRuntime? = None
        for runtime in runtimes {
          if runtime.module_path() == path {
            selected_runtime = Some(runtime)
            break
          }
        }
        let runtime = selected_runtime.unwrap()
        let values = invocation_values(compilation, invocation, global)
        let plan = @executor.plan_recipe_graph(
          compilation,
          [@executor.RecipeRequest::new(invocation.recipe(), arguments=values)],
          global,
          runtime.shell(),
          runtime.cwd(),
          process_environment=runtime.process_environment(),
          options=options.with_echo_quiet(
            options.echo_quiet() || compilation.settings().bool("quiet"),
          ),
        ) catch {
          error => raise Executor(error)
        }
        plans.push(plan)
      }
      let combined = @executor.combine_execution_plans(plans)
      perf_detail_mark("run.sync_plan")
      ignore(perf_detail_emit() catch { _ => () })
      let prefix = fallback_stderr.to_string()
      if prefix == "" {
        return combined
      }
      return combined.with_stderr_prefix(@utf8.encode(prefix))
    }
    for project_invocation in invocations {
      let path = project_invocation.module_path()
      let invocation = project_invocation.invocation()
      let compilation = project.module_compilation(path).unwrap()
      let global = globals[path]
      let mut selected_runtime : @executor.ProjectModuleRuntime? = None
      for runtime in runtimes {
        if runtime.module_path() == path {
          selected_runtime = Some(runtime)
          break
        }
      }
      let runtime = selected_runtime.unwrap()
      let values = invocation_values_async(
        process,
        effects,
        compilation,
        invocation,
        global,
        runtime.context().for_recipe(runtime.cwd(), invocation.recipe(), false),
        runtime.shell(),
      )
      requests.push(
        @executor.ProjectRecipeRequest::new(
          path,
          invocation.recipe(),
          arguments=values,
        ),
      )
    }
    let combined = @executor.plan_project_recipe_graph_async(
      process,
      effects,
      project,
      requests,
      runtimes,
      options~,
      cache_directory~,
    ) catch {
      error => raise Executor(error)
    }
    perf_detail_mark("run.async_plan")
    ignore(perf_detail_emit() catch { _ => () })
    let prefix = fallback_stderr.to_string()
    if prefix == "" {
      return combined
    }
    return combined.with_stderr_prefix(@utf8.encode(prefix))
  }
  raise Query("fallback planning did not terminate")
}
