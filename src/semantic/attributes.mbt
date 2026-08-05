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
  confirm : Bool
  default_value : @syntax.Expression?
  continue_signals : Array[String]
  env : Array[(@syntax.Expression, @syntax.Expression)]
  exit_message : Bool
  extension : String?
  metadata : Array[String]
  no_cd : Bool
  no_exit_message : Bool
  no_quiet : Bool
  parallel : Bool
  positional_arguments : Bool
  arg : Array[@syntax.AttributeArgument]
  cache : Array[@syntax.AttributeArgument]
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
pub fn RecipeAttributes::confirm(self : RecipeAttributes) -> Bool {
  self.confirm
}

///|
pub fn RecipeAttributes::default(
  self : RecipeAttributes,
) -> @syntax.Expression? {
  self.default_value
}

///|
pub fn RecipeAttributes::continue_signals(
  self : RecipeAttributes,
) -> ArrayView[String] {
  self.continue_signals[:]
}

///|
pub fn RecipeAttributes::env(
  self : RecipeAttributes,
) -> ArrayView[(@syntax.Expression, @syntax.Expression)] {
  self.env[:]
}

///|
pub fn RecipeAttributes::exit_message(self : RecipeAttributes) -> Bool {
  self.exit_message
}

///|
pub fn RecipeAttributes::extension(self : RecipeAttributes) -> String? {
  self.extension
}

///|
pub fn RecipeAttributes::metadata(self : RecipeAttributes) -> ArrayView[String] {
  self.metadata[:]
}

///|
pub fn RecipeAttributes::no_cd(self : RecipeAttributes) -> Bool {
  self.no_cd
}

///|
pub fn RecipeAttributes::no_exit_message(self : RecipeAttributes) -> Bool {
  self.no_exit_message
}

///|
pub fn RecipeAttributes::no_quiet(self : RecipeAttributes) -> Bool {
  self.no_quiet
}

///|
pub fn RecipeAttributes::parallel(self : RecipeAttributes) -> Bool {
  self.parallel
}

///|
pub fn RecipeAttributes::positional_arguments(self : RecipeAttributes) -> Bool {
  self.positional_arguments
}

///|
pub fn RecipeAttributes::args(
  self : RecipeAttributes,
) -> ArrayView[@syntax.AttributeArgument] {
  self.arg[:]
}

///|
pub fn RecipeAttributes::cache(
  self : RecipeAttributes,
) -> ArrayView[@syntax.AttributeArgument] {
  self.cache[:]
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
  let mut confirm = false
  let mut default_value : @syntax.Expression? = None
  let continue_signals : Array[String] = []
  let env : Array[(@syntax.Expression, @syntax.Expression)] = []
  let mut exit_message = false
  let mut extension : String? = None
  let metadata : Array[String] = []
  let mut no_cd = false
  let mut no_exit_message = false
  let mut no_quiet = false
  let mut parallel = false
  let mut positional_arguments = false
  let arg : Array[@syntax.AttributeArgument] = []
  let cache : Array[@syntax.AttributeArgument] = []
  let nonrepeatable = [
    "confirm", "default", "doc", "exit-message", "extension", "group", "no-cd", "no-exit-message",
    "no-quiet", "parallel", "positional-arguments", "private", "script", "shell",
    "working-directory",
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
          "arg" =>
            for argument in attribute.arguments() {
              arg.push(argument)
            }
          "cache" =>
            for argument in attribute.arguments() {
              cache.push(argument)
            }
          "confirm" => confirm = true
          "continue" =>
            for argument in attribute.arguments() {
              match argument.value() {
                Some(String(value)) => continue_signals.push(value.cooked())
                _ =>
                  raise AttributeConflict(
                    first="continue",
                    second="non-string",
                    span=attribute.span(),
                  )
              }
            }
          "default" =>
            if attribute.arguments().length() > 0 {
              default_value = attribute.arguments()[0].value()
            }
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
          "env" => {
            let arguments = attribute.arguments()
            if arguments.length() == 2 {
              let first = arguments[0].value()
              let second = arguments[1].value()
              match first {
                Some(first) =>
                  match second {
                    Some(second) => env.push((first, second))
                    None =>
                      raise AttributeConflict(
                        first="env",
                        second="missing-value",
                        span=attribute.span(),
                      )
                  }
                None =>
                  raise AttributeConflict(
                    first="env",
                    second="missing-value",
                    span=attribute.span(),
                  )
              }
            }
          }
          "exit-message" => exit_message = true
          "extension" =>
            match attribute.arguments()[0].value() {
              Some(String(value)) => extension = Some(value.cooked())
              _ =>
                raise AttributeConflict(
                  first="extension",
                  second="non-string",
                  span=attribute.span(),
                )
            }
          "metadata" =>
            for argument in attribute.arguments() {
              match argument.value() {
                Some(String(value)) => metadata.push(value.cooked())
                _ =>
                  raise AttributeConflict(
                    first="metadata",
                    second="non-string",
                    span=attribute.span(),
                  )
              }
            }
          "no-cd" => no_cd = true
          "no-exit-message" => no_exit_message = true
          "no-quiet" => no_quiet = true
          "parallel" => parallel = true
          "positional-arguments" => positional_arguments = true
          "shell" =>
            for argument in attribute.arguments() {
              match argument.value() {
                Some(value) => shell.push(value)
                None =>
                  raise AttributeConflict(
                    first="shell",
                    second="missing-value",
                    span=attribute.span(),
                  )
              }
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
  if names.contains("exit-message") && names.contains("no-exit-message") {
    raise AttributeConflict(
      first="exit-message",
      second="no-exit-message",
      span=attributes[0].span(),
    )
  }
  {
    names,
    platform,
    private,
    doc,
    group,
    working_directory,
    shell,
    script,
    confirm,
    default_value,
    continue_signals,
    env,
    exit_message,
    extension,
    metadata,
    no_cd,
    no_exit_message,
    no_quiet,
    parallel,
    positional_arguments,
    arg,
    cache,
  }
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
