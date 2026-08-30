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
  if !@planner.valid_timestamp_format(format) {
    raise Query(
      "failed to parse time format string `\{format}`: bad or unsupported format string",
    )
  }
  let millis = @host.HostClock::now_millis(effects) catch {
    error => raise Host(error)
  }
  Some(@planner.format_timestamp(millis, format))
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
