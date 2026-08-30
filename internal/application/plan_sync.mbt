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
/// The synchronous planner is safe for a deliberately narrow dry-run shape.
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
