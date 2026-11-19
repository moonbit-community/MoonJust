///|
/// Static value category required by one registered setting.
#derive(Eq, Debug)
pub(all) enum SettingKind {
  Boolean
  Text
  Expression
}

///|
#derive(Eq, Debug)
pub(all) struct SettingSpec {
  name : String
  kind : SettingKind
  required : Bool
}

///|
pub fn SettingSpec::new(
  name : String,
  kind : SettingKind,
  required : Bool,
) -> SettingSpec {
  { name, kind, required, }
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
let registered_settings : Array[SettingSpec] = [
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
]

///|
pub fn setting_specs() -> ArrayView[SettingSpec] {
  registered_settings[:]
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
