///|
pub struct DotenvOptions {
  load : Bool
  override_environment : Bool
  required : Bool
  lists : Bool
  filenames : Array[String]
  paths : Array[String]
}

///|
pub fn DotenvOptions::new(
  load~ : Bool = false,
  override_environment~ : Bool = false,
  required~ : Bool = false,
  lists~ : Bool = false,
  filenames~ : Array[String] = [],
  paths~ : Array[String] = [],
) -> DotenvOptions {
  {
    load,
    override_environment,
    required,
    lists,
    filenames: filenames.copy(),
    paths: paths.copy(),
  }
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
async fn[T : @host.HostFs] load_file(
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
  let limit = @lexer.LexerLimits::default().max_source_bytes()
  let bytes = @host.HostFs::read_source(host, path, limit) catch {
    error => raise redacted_host_error(error)
  }
  if bytes.length() > limit {
    raise SourceAccess
  }
  let text = @utf8.decode(bytes) catch { _ => raise InvalidUtf8(path~) }
  Some(
    parse_dotenv(text, ambient~) catch {
      Parse(line~, column~) => raise ParseFile(path~, line~, column~)
      ParseValue(line~, column~, value~, index~) =>
        raise ParseFileValue(path~, line~, column~, value~, index~)
      error => raise error
    },
  )
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
pub async fn[T : @host.HostFs] load_dotenv_files(
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
    return EnvTable::new(name_mode=ambient.name_mode())
  }
  let result = EnvTable::new(name_mode=ambient.name_mode())
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
