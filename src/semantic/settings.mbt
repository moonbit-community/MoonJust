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
/// Static value category required by one registered setting.
pub(all) enum SettingKind {
  Boolean
  Text
  Expression
} derive(Eq, Debug)

///|
pub(all) struct SettingSpec {
  name : String
  kind : SettingKind
  required : Bool
} derive(Eq, Debug)

///|
pub fn SettingSpec::new(
  name : String,
  kind : SettingKind,
  required : Bool,
) -> SettingSpec {
  { name, kind, required }
}

///|
pub fn SettingSpec::name(self : SettingSpec) -> String {
  self.name
}

///|
pub fn SettingSpec::kind(self : SettingSpec) -> SettingKind {
  self.kind
}

///|
pub fn SettingSpec::required(self : SettingSpec) -> Bool {
  self.required
}

///|
pub fn setting_specs() -> ArrayView[SettingSpec] {
  [
    SettingSpec::new("allow-duplicate-recipes", Boolean, false),
    SettingSpec::new("allow-duplicate-variables", Boolean, false),
    SettingSpec::new("default-list", Boolean, false),
    SettingSpec::new("default-script", Boolean, false),
    SettingSpec::new("dotenv-command", Expression, true),
    SettingSpec::new("dotenv-filename", Expression, true),
    SettingSpec::new("dotenv-load", Boolean, false),
    SettingSpec::new("dotenv-override", Boolean, false),
    SettingSpec::new("dotenv-path", Expression, true),
    SettingSpec::new("dotenv-required", Boolean, false),
    SettingSpec::new("export", Boolean, false),
    SettingSpec::new("fallback", Boolean, false),
    SettingSpec::new("guards", Boolean, false),
    SettingSpec::new("ignore-comments", Boolean, false),
    SettingSpec::new("indentation", Text, true),
    SettingSpec::new("lazy", Boolean, false),
    SettingSpec::new("lists", Boolean, false),
    SettingSpec::new("minimum-version", Text, true),
    SettingSpec::new("no-cd", Boolean, false),
    SettingSpec::new("no-exit-message", Boolean, false),
    SettingSpec::new("positional-arguments", Boolean, false),
    SettingSpec::new("quiet", Boolean, false),
    SettingSpec::new("script-interpreter", Expression, true),
    SettingSpec::new("shell", Expression, true),
    SettingSpec::new("tempdir", Expression, true),
    SettingSpec::new("unstable", Boolean, false),
    SettingSpec::new("windows-powershell", Boolean, false),
    SettingSpec::new("windows-shell", Expression, true),
    SettingSpec::new("working-directory", Expression, true),
  ][:]
}

///|
pub fn setting_spec(name : String) -> SettingSpec? {
  for spec in setting_specs() {
    if spec.name() == name {
      return Some(spec)
    }
  }
  None
}

///|
pub fn SettingValue::as_bool(self : SettingValue) -> Bool? {
  match self {
    Flag => Some(true)
    Boolean(value) => Some(value)
    Text(_) | Expression(_) => None
  }
}

///|
pub fn SettingValue::as_text(self : SettingValue) -> String? {
  match self {
    Text(value) => Some(value)
    _ => None
  }
}

///|
pub struct CompiledSettings {
  values : Map[String, SettingValue]
  ordered : Array[String]
  spans : Map[String, @source.Span]
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
pub fn CompiledSettings::span(
  self : CompiledSettings,
  name : String,
) -> @source.Span? {
  self.spans.get(name)
}

///|
pub fn CompiledSettings::bool(self : CompiledSettings, name : String) -> Bool {
  match self.values.get(name) {
    Some(value) => value.as_bool().unwrap_or(false)
    None => false
  }
}

///|
pub fn CompiledSettings::kind(
  self : CompiledSettings,
  name : String,
) -> SettingKind? {
  ignore(self)
  setting_spec(name).map(fn(spec) { spec.kind() })
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
fn setting_value_valid(name : String, value : SettingValue) -> Bool {
  match setting_spec(name) {
    None => false
    Some(spec) =>
      match spec.kind() {
        Boolean =>
          match value {
            Flag | Boolean(_) => true
            _ => false
          }
        Text => value is Text(_)
        Expression =>
          match value {
            Text(_) => true
            Expression(_) => true
            _ => false
          }
      }
  }
}

///|
fn indentation_error(value : String) -> String? {
  if value.is_empty() {
    return Some("indentation must not be empty")
  }
  let mut spaces = false
  let mut tabs = false
  for character in value {
    match character {
      ' ' => spaces = true
      '\t' => tabs = true
      _ => return Some("indentation must be spaces or tabs")
    }
  }
  if spaces && tabs {
    Some("indentation may not be mixed")
  } else {
    None
  }
}

///|
fn setting_name_span(setting : @syntax.Setting) -> @source.Span {
  try! @source.Span::new(
    setting.span().source_id(),
    setting.span().start_byte() + 4,
    setting.span().start_byte() + 4 + setting.name().length(),
  )
}

///|
fn compile_settings(
  settings : Array[@syntax.Setting],
) -> CompiledSettings raise SemanticError {
  let values : Map[String, SettingValue] = Map([])
  let ordered : Array[String] = []
  let spans : Map[String, @source.Span] = Map([])
  for setting in settings {
    let name = setting.name()
    if name == "minimum-version" {
      match setting.value() {
        Some(String(value)) if (value.kind() == Raw || value.kind() == Cooked) &&
          !value.shell_expanded() => ()
        _ => raise InvalidSettingValue(name~, span=setting_name_span(setting))
      }
    }
    let value = setting_value(setting)
    if !setting_value_valid(name, value) {
      raise InvalidSettingValue(name~, span=setting.span())
    }
    if name == "indentation" && value is Text(indentation) {
      match indentation_error(indentation) {
        Some(message) => raise InvalidIndentation(message~, span=setting.span())
        None => ()
      }
    }
    if !values.contains(name) {
      ordered.push(name)
    }
    values[name] = value
    spans[name] = setting_name_span(setting)
  }
  let conflicts = [
    ("dotenv-command", "dotenv-filename"),
    ("dotenv-command", "dotenv-load"),
    ("dotenv-command", "dotenv-path"),
    ("dotenv-command", "dotenv-required"),
    ("no-cd", "working-directory"),
  ]
  for pair in conflicts {
    let first = pair.0
    let second = pair.1
    let first_enabled = match values.get(first) {
      Some(value) => value.as_bool().unwrap_or(true)
      None => false
    }
    let second_enabled = match values.get(second) {
      Some(value) => value.as_bool().unwrap_or(true)
      None => false
    }
    if values.contains(first) &&
      values.contains(second) &&
      first_enabled &&
      second_enabled {
      let span = settings[settings.length() - 1].span()
      raise SettingConflict(first~, second~, span~)
    }
  }
  { values, ordered, spans }
}
