///|
pub struct DotenvOptions {
  load : Bool
  override_environment : Bool
  required : Bool
  lists : Bool
  dry_run : Bool
  filenames : Array[String]
  paths : Array[String]
  commands : Array[@host.CommandSpec]
}

///|
pub fn DotenvOptions::new(
  load? : Bool = false,
  override_environment? : Bool = false,
  required? : Bool = false,
  lists? : Bool = false,
  dry_run? : Bool = false,
  filenames? : Array[String] = [],
  paths? : Array[String] = [],
  commands? : Array[@host.CommandSpec] = [],
) -> DotenvOptions {
  {
    load,
    override_environment,
    required,
    lists,
    dry_run,
    filenames: filenames.copy(),
    paths: paths.copy(),
    commands: commands.copy(),
  }
}

///|
fn command_in_directory(
  command : @host.CommandSpec,
  working_directory : @path.PathValue,
) -> @host.CommandSpec raise DotenvError {
  let copy = @host.CommandSpec::new(
    command.program(),
    command.arguments().to_owned(),
  ) catch {
    error => raise redacted_host_error(error)
  }
  copy.set_cwd(working_directory)
  for entry in command.environment() {
    copy.add_environment(entry.0, entry.1) catch {
      error => raise redacted_host_error(error)
    }
  }
  copy.set_stdin(command.stdin().to_owned())
  copy
}

///|
fn resolved(
  base : @path.PathValue,
  value : String,
) -> @path.PathValue raise DotenvError {
  let child = @path.PathValue::new(value, base.flavor()) catch {
    _ => raise InvalidPath
  }
  base.join(child) catch {
    _ => raise InvalidPath
  }
}

///|
fn[T : @host.HostFs] load_file(
  host : T,
  path : @path.PathValue,
  ambient : EnvTable,
) -> EnvTable? raise DotenvError {
  let exists = @host.HostFs::file_exists(host, path) catch {
    error => raise redacted_host_error(error)
  }
  if !exists {
    return None
  }
  let metadata = @host.HostFs::metadata(host, path) catch {
    NotFound(_) => return None
    error => raise redacted_host_error(error)
  }
  if metadata.is_directory() {
    return None
  }
  let bytes = @host.HostFs::read_file(host, path) catch {
    error => raise redacted_host_error(error)
  }
  let text = @utf8.decode(bytes) catch { _ => raise InvalidUtf8(path~) }
  Some(parse_dotenv(text, ambient~))
}

///|
fn merge_loaded(
  accumulated : EnvTable,
  loaded : EnvTable,
  ambient : EnvTable,
  override_environment : Bool,
) -> Unit {
  for entry in loaded.entries() {
    if override_environment || !ambient.contains(entry.0) {
      accumulated.set(entry.0, entry.1)
    }
  }
}

///|
pub fn[T : @host.HostFs] load_dotenv_files(
  host : T,
  working_directory : @path.PathValue,
  ambient : EnvTable,
  options : DotenvOptions,
) -> EnvTable raise DotenvError {
  if !options.lists &&
    (options.filenames.length() > 1 || options.paths.length() > 1) {
    raise ArgumentsRequireLists
  }
  if !options.load &&
    !options.override_environment &&
    !options.required &&
    options.filenames.is_empty() &&
    options.paths.is_empty() {
    return EnvTable::new()
  }
  let result = EnvTable::new()
  let mut found = false
  for value in options.paths {
    let path = resolved(working_directory, value)
    match load_file(host, path, ambient) {
      Some(loaded) => {
        merge_loaded(result, loaded, ambient, options.override_environment)
        found = true
      }
      None => ()
    }
  }
  if found {
    return result
  }
  let filenames = if options.filenames.is_empty() {
    [".env"]
  } else {
    options.filenames
  }
  let mut directory = Some(working_directory)
  while directory is Some(current) {
    for filename in filenames {
      let path = resolved(current, filename)
      match load_file(host, path, ambient) {
        Some(loaded) => {
          merge_loaded(result, loaded, ambient, options.override_environment)
          found = true
        }
        None => ()
      }
    }
    if found {
      return result
    }
    directory = current.parent()
  }
  if options.required {
    raise Required
  }
  result
}

///|
pub fn[T : @host.HostProcess] load_dotenv_commands(
  host : T,
  working_directory : @path.PathValue,
  ambient : EnvTable,
  options : DotenvOptions,
) -> EnvTable raise DotenvError {
  let result = EnvTable::new()
  if options.dry_run {
    return result
  }
  for index, command in options.commands {
    let request = command_in_directory(command, working_directory)
    let output = @host.HostProcess::run_process(host, request) catch {
      _ => raise CommandUnavailable(index=index + 1)
    }
    if output.exit_code() != 0 {
      raise CommandFailed(index=index + 1, exit_code=output.exit_code())
    }
    let text = @utf8.decode(output.stdout()) catch {
      _ => raise Parse(line=1, column=1)
    }
    let loaded = parse_dotenv(text, ambient~)
    merge_loaded(result, loaded, ambient, options.override_environment)
  }
  result
}

///|
pub fn[T : @host.HostFs + @host.HostProcess] load_dotenv(
  host : T,
  working_directory : @path.PathValue,
  ambient : EnvTable,
  options : DotenvOptions,
) -> EnvTable raise DotenvError {
  if !options.commands.is_empty() {
    load_dotenv_commands(host, working_directory, ambient, options)
  } else {
    load_dotenv_files(host, working_directory, ambient, options)
  }
}
