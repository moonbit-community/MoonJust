///|
/// Compiled recipe metadata, with platform selection separated from execution.
pub struct RecipeAttributes {
  names : Array[String]
  platform : TargetOs?
  private : Bool
  doc : String?
  group : String?
  working_directory : @syntax.Expression?
  shell : Array[@syntax.Expression]
  script : Bool
} derive(Debug)

///|
pub fn RecipeAttributes::names(self : RecipeAttributes) -> ArrayView[String] {
  self.names[:]
}

///|
pub fn RecipeAttributes::platform(self : RecipeAttributes) -> TargetOs? {
  self.platform
}

///|
pub fn RecipeAttributes::private(self : RecipeAttributes) -> Bool {
  self.private
}

///|
pub fn RecipeAttributes::doc(self : RecipeAttributes) -> String? {
  self.doc
}

///|
pub fn RecipeAttributes::group(self : RecipeAttributes) -> String? {
  self.group
}

///|
pub fn RecipeAttributes::working_directory(
  self : RecipeAttributes,
) -> @syntax.Expression? {
  self.working_directory
}

///|
pub fn RecipeAttributes::shell(
  self : RecipeAttributes,
) -> ArrayView[@syntax.Expression] {
  self.shell[:]
}

///|
pub fn RecipeAttributes::script(self : RecipeAttributes) -> Bool {
  self.script
}

///|
fn platform_for(name : String) -> TargetOs? {
  match name {
    "linux" => Some(Linux)
    "macos" => Some(Macos)
    "windows" => Some(Windows)
    "android" => Some(Android)
    "dragonfly" => Some(Dragonfly)
    "freebsd" => Some(Freebsd)
    "netbsd" => Some(Netbsd)
    "openbsd" => Some(Openbsd)
    "unix" => Some(Unix)
    _ => None
  }
}

///|
fn compile_attributes(
  attributes : ArrayView[@syntax.Attribute],
) -> RecipeAttributes raise SemanticError {
  let names : Array[String] = []
  let mut platform : TargetOs? = None
  let mut private = false
  let mut doc : String? = None
  let mut group : String? = None
  let mut working_directory : @syntax.Expression? = None
  let shell : Array[@syntax.Expression] = []
  let mut script = false
  let nonrepeatable = [
    "private", "doc", "group", "working-directory", "shell", "script",
  ]
  for attribute in attributes {
    let name = attribute.name()
    if nonrepeatable.contains(name) && names.contains(name) {
      raise AttributeConflict(first=name, second=name, span=attribute.span())
    }
    names.push(name)
    match platform_for(name) {
      Some(value) => {
        if platform is Some(_) {
          raise AttributeConflict(
            first="platform",
            second=name,
            span=attribute.span(),
          )
        }
        platform = Some(value)
      }
      None =>
        match name {
          "private" => private = true
          "doc" =>
            if attribute.arguments().length() > 0 {
              let argument = attribute.arguments()[0]
              match argument.value() {
                Some(String(value)) => doc = Some(value.cooked())
                _ =>
                  raise AttributeConflict(
                    first="doc",
                    second="non-string",
                    span=attribute.span(),
                  )
              }
            } else {
              raise AttributeConflict(
                first="doc",
                second="missing-value",
                span=attribute.span(),
              )
            }
          "group" =>
            if attribute.arguments().length() > 0 {
              let argument = attribute.arguments()[0]
              match argument.value() {
                Some(String(value)) => group = Some(value.cooked())
                _ =>
                  raise AttributeConflict(
                    first="group",
                    second="non-string",
                    span=attribute.span(),
                  )
              }
            } else {
              raise AttributeConflict(
                first="group",
                second="missing-value",
                span=attribute.span(),
              )
            }
          "working-directory" =>
            if attribute.arguments().length() > 0 {
              working_directory = attribute.arguments()[0].value()
            }
          "shell" =>
            for argument in attribute.arguments() {
              shell.push(argument.value().unwrap())
            }
          "script" => script = true
          _ => ()
        }
    }
  }
  if names.contains("no-cd") && names.contains("working-directory") {
    raise AttributeConflict(
      first="no-cd",
      second="working-directory",
      span=attributes[0].span(),
    )
  }
  if names.contains("script") && names.contains("shell") {
    raise AttributeConflict(
      first="script",
      second="shell",
      span=attributes[0].span(),
    )
  }
  { names, platform, private, doc, group, working_directory, shell, script }
}

///|
pub fn RecipeAttributes::matches(
  self : RecipeAttributes,
  platform : TargetPlatform,
) -> Bool {
  match self.platform {
    None => true
    Some(Unix) => platform.is_unix()
    Some(expected) => expected == platform.operating_system()
  }
}
