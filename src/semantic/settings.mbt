///|
/// Operating systems used by platform attributes in the pure semantic layer.
pub(all) enum TargetOs {
  Linux
  Macos
  Windows
  Android
  Dragonfly
  Freebsd
  Netbsd
  Openbsd
  Unix
  Other(String)
} derive(Eq, Hash, Debug)

///|
/// Target facts supplied by the caller; no host or FFI dependency is needed.
pub(all) struct TargetPlatform {
  operating_system : TargetOs
  is_unix : Bool
} derive(Eq, Debug)

///|
pub fn TargetPlatform::new(
  operating_system : TargetOs,
  is_unix : Bool,
) -> TargetPlatform {
  { operating_system, is_unix }
}

///|
pub fn TargetPlatform::operating_system(self : TargetPlatform) -> TargetOs {
  self.operating_system
}

///|
pub fn TargetPlatform::is_unix(self : TargetPlatform) -> Bool {
  self.is_unix
}

///|
/// A setting retains its expression while exposing a typed category to users.
pub(all) enum SettingValue {
  Flag
  Boolean(Bool)
  Text(String)
  Expression(@syntax.Expression)
} derive(Eq, Debug)

///|
pub fn SettingValue::as_bool(self : SettingValue) -> Bool? {
  match self {
    Flag => Some(true)
    Boolean(value) => Some(value)
    Text(_) | Expression(_) => None
  }
}

///|
pub struct CompiledSettings {
  values : Map[String, SettingValue]
  ordered : Array[String]
} derive(Debug)

///|
pub fn CompiledSettings::names(self : CompiledSettings) -> ArrayView[String] {
  self.ordered[:]
}

///|
pub fn CompiledSettings::get(
  self : CompiledSettings,
  name : String,
) -> SettingValue? {
  self.values.get(name)
}

///|
pub fn CompiledSettings::has(self : CompiledSettings, name : String) -> Bool {
  self.values.contains(name)
}

///|
pub fn CompiledSettings::bool(self : CompiledSettings, name : String) -> Bool {
  match self.values.get(name) {
    Some(value) => value.as_bool().unwrap_or(false)
    None => false
  }
}

///|
fn setting_value(setting : @syntax.Setting) -> SettingValue {
  match setting.value() {
    None => Flag
    Some(Boolean(value~, ..)) => Boolean(value)
    Some(String(value)) => Text(value.cooked())
    Some(expression) => Expression(expression)
  }
}

///|
fn compile_settings(
  settings : Array[@syntax.Setting],
) -> CompiledSettings raise SemanticError {
  let values : Map[String, SettingValue] = Map([])
  let ordered : Array[String] = []
  for setting in settings {
    let name = setting.name()
    if !values.contains(name) {
      ordered.push(name)
    }
    values[name] = setting_value(setting)
  }
  let conflicts = [
    ("dotenv-command", "dotenv-filename"),
    ("dotenv-command", "dotenv-load"),
    ("dotenv-command", "dotenv-override"),
    ("dotenv-command", "dotenv-path"),
    ("dotenv-command", "dotenv-required"),
    ("no-cd", "working-directory"),
  ]
  for pair in conflicts {
    let first = pair.0
    let second = pair.1
    if values.contains(first) && values.contains(second) {
      let span = settings[settings.length() - 1].span()
      raise SettingConflict(first~, second~, span~)
    }
  }
  { values, ordered }
}
