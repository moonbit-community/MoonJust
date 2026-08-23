///|
/// Stable failures produced while composing execution environment settings.
/// Override values and environment values are never retained in errors.
pub(all) suberror EnvironmentConfigError {
  InvalidOverridePath(path~ : String)
  EmptyShell
  Path(@path.PathError)
} derive(Eq, Debug)

///|
pub fn EnvironmentConfigError::message(self : EnvironmentConfigError) -> String {
  match self {
    InvalidOverridePath(path~) => "invalid override path `\{path}`"
    EmptyShell => "shell program must not be empty"
    Path(_) => "invalid temporary directory"
  }
}

///|
fn identifier_start(character : Char) -> Bool {
  character.is_ascii_alphabetic() || character == '_'
}

///|
fn identifier_continue(character : Char) -> Bool {
  identifier_start(character) || character.is_ascii_digit() || character == '-'
}

///|
fn valid_identifier(value : String) -> Bool {
  let characters = value.to_array()
  guard characters.get(0) is Some(first) else { return false }
  if !identifier_start(first) {
    return false
  }
  for character in characters[1:] {
    if !identifier_continue(character) {
      return false
    }
  }
  true
}

///|
/// One command-line variable override. It is intentionally not `Debug` so a
/// value cannot be exposed through structural diagnostics.
pub struct VariableOverride {
  modules : Array[String]
  name : String
  value : String
}

///|
pub fn VariableOverride::parse(
  path : String,
  value : String,
) -> VariableOverride raise EnvironmentConfigError {
  let components : Array[String] = []
  for component in path.split("::") {
    let name = component.to_owned()
    if !valid_identifier(name) {
      raise InvalidOverridePath(path~)
    }
    components.push(name)
  }
  if components.is_empty() {
    raise InvalidOverridePath(path~)
  }
  let name = components.pop().unwrap()
  { modules: components, name, value }
}

///|
pub fn VariableOverride::modules(self : VariableOverride) -> ArrayView[String] {
  self.modules[:]
}

///|
pub fn VariableOverride::name(self : VariableOverride) -> String {
  self.name
}

///|
pub fn VariableOverride::value(self : VariableOverride) -> String {
  self.value
}

///|
pub fn VariableOverride::path(self : VariableOverride) -> String {
  let components = self.modules.copy()
  components.push(self.name)
  components.join("::")
}

///|
/// Deterministic, last-wins variable overrides keyed by module path and name.
/// Like `VariableOverride`, the table has no structural debug representation.
pub struct OverrideTable {
  values : Map[String, VariableOverride]
  ordered : Array[String]
}

///|
pub fn OverrideTable::new() -> OverrideTable {
  { values: Map([]), ordered: [] }
}

///|
pub fn OverrideTable::from_entries(
  entries : ArrayView[(String, String)],
) -> OverrideTable raise EnvironmentConfigError {
  let table = OverrideTable::new()
  for entry in entries {
    table.set(VariableOverride::parse(entry.0, entry.1))
  }
  table
}

///|
pub fn OverrideTable::set(
  self : OverrideTable,
  entry : VariableOverride,
) -> Unit {
  let path = entry.path()
  if !self.values.contains(path) {
    self.ordered.push(path)
  }
  self.values[path] = entry
}

///|
pub fn OverrideTable::get(
  self : OverrideTable,
  path : String,
) -> VariableOverride? {
  self.values.get(path)
}

///|
pub fn OverrideTable::entries(self : OverrideTable) -> Array[VariableOverride] {
  self.ordered.map(fn(path) { self.values[path] })
}

///|
/// Host platform facts interpreted for environment composition. The wrapper
/// prevents target conditionals from entering pure configuration code.
pub struct PlatformConfiguration {
  info : @host.PlatformInfo
} derive(Eq, Debug)

///|
pub fn PlatformConfiguration::new(
  info : @host.PlatformInfo,
) -> PlatformConfiguration {
  { info, }
}

///|
pub fn[T : @host.HostPlatform] platform_configuration(
  host : T,
) -> PlatformConfiguration raise @host.HostError {
  PlatformConfiguration::new(@host.HostPlatform::platform_info(host))
}

///|
pub fn PlatformConfiguration::info(
  self : PlatformConfiguration,
) -> @host.PlatformInfo {
  self.info
}

///|
pub fn PlatformConfiguration::is_windows(self : PlatformConfiguration) -> Bool {
  self.info.operating_system() == Windows
}

///|
pub fn PlatformConfiguration::environment_name_mode(
  self : PlatformConfiguration,
) -> EnvNameMode {
  if self.is_windows() {
    AsciiInsensitive
  } else {
    Sensitive
  }
}

///|
/// Fully selected recipe shell and arguments.
pub struct ShellConfiguration {
  program : String
  arguments : Array[String]
} derive(Eq, Debug)

///|
pub fn ShellConfiguration::new(
  program : String,
  arguments : Array[String],
) -> ShellConfiguration raise EnvironmentConfigError {
  if program.is_empty() {
    raise EmptyShell
  }
  { program, arguments: arguments.copy() }
}

///|
pub fn ShellConfiguration::program(self : ShellConfiguration) -> String {
  self.program
}

///|
pub fn ShellConfiguration::arguments(
  self : ShellConfiguration,
) -> ArrayView[String] {
  self.arguments[:]
}

///|
/// Resolve CLI and justfile shell settings with upstream precedence. Supplying
/// CLI shell arguments without a CLI shell deliberately selects `sh`, even on
/// Windows, matching just 1.57.0.
pub fn resolve_shell(
  platform : PlatformConfiguration,
  cli_shell? : String? = None,
  cli_arguments? : Array[String]? = None,
  setting_shell? : ShellConfiguration? = None,
  windows_shell? : ShellConfiguration? = None,
  windows_powershell? : Bool = false,
) -> ShellConfiguration raise EnvironmentConfigError {
  match (cli_shell, cli_arguments) {
    (Some(program), Some(arguments)) =>
      return ShellConfiguration::new(program, arguments)
    (Some(program), None) => return ShellConfiguration::new(program, ["-cu"])
    (None, Some(arguments)) => return ShellConfiguration::new("sh", arguments)
    (None, None) => ()
  }
  if platform.is_windows() {
    match windows_shell {
      Some(shell) => return shell
      None => ()
    }
    if windows_powershell {
      return ShellConfiguration::new("powershell.exe", ["-NoLogo", "-Command"])
    }
  }
  setting_shell.unwrap_or(try! ShellConfiguration::new("sh", ["-cu"]))
}

///|
pub(all) enum TemporaryDirectorySource {
  CommandLine
  Setting
  HostDefault
} derive(Eq, Debug)

///|
/// Selected parent for per-recipe temporary directories. `None` delegates to
/// the host runtime directory or operating-system default.
pub struct TemporaryDirectoryConfiguration {
  source : TemporaryDirectorySource
  directory : @path.PathValue?
} derive(Eq, Debug)

///|
pub fn TemporaryDirectoryConfiguration::source(
  self : TemporaryDirectoryConfiguration,
) -> TemporaryDirectorySource {
  self.source
}

///|
pub fn TemporaryDirectoryConfiguration::directory(
  self : TemporaryDirectoryConfiguration,
) -> @path.PathValue? {
  self.directory
}

///|
fn resolve_directory(
  project_directory : @path.PathValue,
  value : String,
) -> @path.PathValue raise EnvironmentConfigError {
  let path = @path.PathValue::new(value, project_directory.flavor()) catch {
    error => raise Path(error)
  }
  project_directory.join(path) catch {
    error => raise Path(error)
  }
}

///|
pub fn resolve_temporary_directory(
  project_directory : @path.PathValue,
  cli_tempdir? : String? = None,
  setting_tempdir? : String? = None,
) -> TemporaryDirectoryConfiguration raise EnvironmentConfigError {
  match cli_tempdir {
    Some(value) =>
      {
        source: CommandLine,
        directory: Some(resolve_directory(project_directory, value)),
      }
    None =>
      match setting_tempdir {
        Some(value) =>
          {
            source: Setting,
            directory: Some(resolve_directory(project_directory, value)),
          }
        None => { source: HostDefault, directory: None }
      }
  }
}

///|
/// Compose the exact environment visible to a recipe command. `dotenv` is
/// already filtered by `DotenvOptions.override_environment`; later layers
/// always win. Module unexports remove inherited values before exported recipe
/// parameters and `[env]` attributes are applied.
pub fn compose_process_environment(
  ambient : EnvTable,
  dotenv : EnvTable,
  exported_variables : EnvTable,
  exported_parameters : EnvTable,
  recipe_environment : EnvTable,
  unexports? : ArrayView[String] = [],
) -> EnvTable {
  let result = EnvTable::from_entries(
    ambient.entries()[:],
    name_mode=ambient.name_mode(),
  )
  result.merge(dotenv)
  result.merge(exported_variables)
  for name in unexports {
    result.remove(name)
  }
  result.merge(exported_parameters)
  result.merge(recipe_environment)
  result
}

///|
/// Pure execution configuration assembled at the CLI/application boundary.
/// Evaluated setting values are inputs so this layer performs no evaluator or
/// host side effects.
pub struct EnvironmentConfiguration {
  platform : PlatformConfiguration
  overrides : OverrideTable
  shell : ShellConfiguration
  temporary_directory : TemporaryDirectoryConfiguration
}

///|
pub fn EnvironmentConfiguration::new(
  platform : @host.PlatformInfo,
  project_directory : @path.PathValue,
  variable_overrides : ArrayView[(String, String)],
  cli_shell? : String? = None,
  cli_shell_arguments? : Array[String]? = None,
  cli_tempdir? : String? = None,
  setting_shell? : ShellConfiguration? = None,
  setting_tempdir? : String? = None,
  windows_shell? : ShellConfiguration? = None,
  windows_powershell? : Bool = false,
) -> EnvironmentConfiguration raise EnvironmentConfigError {
  let platform = PlatformConfiguration::new(platform)
  {
    platform,
    overrides: OverrideTable::from_entries(variable_overrides),
    shell: resolve_shell(
      platform,
      cli_shell~,
      cli_arguments=cli_shell_arguments,
      setting_shell~,
      windows_shell~,
      windows_powershell~,
    ),
    temporary_directory: resolve_temporary_directory(
      project_directory,
      cli_tempdir~,
      setting_tempdir~,
    ),
  }
}

///|
pub fn EnvironmentConfiguration::platform(
  self : EnvironmentConfiguration,
) -> PlatformConfiguration {
  self.platform
}

///|
pub fn EnvironmentConfiguration::overrides(
  self : EnvironmentConfiguration,
) -> OverrideTable {
  self.overrides
}

///|
pub fn EnvironmentConfiguration::shell(
  self : EnvironmentConfiguration,
) -> ShellConfiguration {
  self.shell
}

///|
pub fn EnvironmentConfiguration::temporary_directory(
  self : EnvironmentConfiguration,
) -> TemporaryDirectoryConfiguration {
  self.temporary_directory
}
