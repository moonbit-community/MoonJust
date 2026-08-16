///|
/// Compiled recipe metadata, with platform selection separated from execution.
pub struct RecipeAttributes {
  names : Array[String]
  platforms : Array[TargetOs]
  private : Bool
  doc : String?
  doc_expression : @syntax.Expression?
  groups : Array[String]
  working_directory : @syntax.Expression?
  shell : Array[@syntax.Expression]
  script : Bool
  script_interpreter : Array[@syntax.Expression]
  confirm : Bool
  confirm_prompt : @syntax.Expression?
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
  self.platforms.get(0)
}

///|
pub fn RecipeAttributes::platforms(
  self : RecipeAttributes,
) -> ArrayView[TargetOs] {
  self.platforms[:]
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
pub fn RecipeAttributes::doc_expression(
  self : RecipeAttributes,
) -> @syntax.Expression? {
  self.doc_expression
}

///|
pub fn RecipeAttributes::group(self : RecipeAttributes) -> String? {
  self.groups.get(0)
}

///|
pub fn RecipeAttributes::groups(self : RecipeAttributes) -> ArrayView[String] {
  self.groups[:]
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
pub fn RecipeAttributes::script_interpreter(
  self : RecipeAttributes,
) -> ArrayView[@syntax.Expression] {
  self.script_interpreter[:]
}

///|
pub fn RecipeAttributes::confirm(self : RecipeAttributes) -> Bool {
  self.confirm
}

///|
pub fn RecipeAttributes::confirm_prompt(
  self : RecipeAttributes,
) -> @syntax.Expression? {
  self.confirm_prompt
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
fn attribute_lexical_compare(left : String, right : String) -> Int {
  let length = Int::min(left.length(), right.length())
  for index in 0..<length {
    let order = left.unsafe_get(index).compare(right.unsafe_get(index))
    if order != 0 {
      return order
    }
  }
  left.length().compare(right.length())
}

///|
fn compile_attributes(
  attributes : ArrayView[@syntax.Attribute],
  recipe_name? : String,
  recipe_span? : @source.Span,
) -> RecipeAttributes raise SemanticError {
  let names : Array[String] = []
  let platforms : Array[TargetOs] = []
  let mut private = false
  let mut doc : String? = None
  let mut doc_expression : @syntax.Expression? = None
  let groups : Array[String] = []
  let mut working_directory : @syntax.Expression? = None
  let shell : Array[@syntax.Expression] = []
  let mut script = false
  let script_interpreter : Array[@syntax.Expression] = []
  let mut confirm = false
  let mut confirm_prompt : @syntax.Expression? = None
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
    "confirm", "default", "doc", "exit-message", "extension", "no-cd", "no-exit-message",
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
        if platforms.contains(value) {
          raise AttributeConflict(
            first=name,
            second=name,
            span=attribute.span(),
          )
        }
        platforms.push(value)
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
          "confirm" => {
            confirm = true
            if attribute.arguments().length() == 1 {
              confirm_prompt = attribute.arguments()[0].value()
            }
          }
          "continue" =>
            for argument in attribute.arguments() {
              match argument.value() {
                Some(String(value)) => {
                  let signal = value.cooked()
                  if signal != "SIGHUP" &&
                    signal != "SIGINT" &&
                    signal != "SIGQUIT" {
                    raise InvalidContinueSignal(signal~, span=argument.span())
                  }
                  continue_signals.push(signal)
                }
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
              doc_expression = argument.value()
              match argument.value() {
                Some(String(value)) => doc = Some(value.cooked())
                _ => ()
              }
            }
          "group" =>
            if attribute.arguments().length() > 0 {
              let argument = attribute.arguments()[0]
              match argument.value() {
                Some(String(value)) => {
                  let group = value.cooked()
                  if groups.contains(group) {
                    raise AttributeConflict(
                      first="group",
                      second="group",
                      span=attribute.span(),
                    )
                  }
                  groups.push(group)
                }
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
          "script" => {
            script = true
            for argument in attribute.arguments() {
              match argument.value() {
                Some(value) => script_interpreter.push(value)
                None =>
                  raise AttributeConflict(
                    first="script",
                    second="missing-value",
                    span=attribute.span(),
                  )
              }
            }
          }
          _ => ()
        }
    }
  }
  if names.contains("no-cd") && names.contains("working-directory") {
    match (recipe_name, recipe_span) {
      (Some(recipe), Some(span)) =>
        raise NoCdWorkingDirectoryAttributes(recipe~, span~)
      _ =>
        raise AttributeConflict(
          first="no-cd",
          second="working-directory",
          span=attributes[0].span(),
        )
    }
  }
  if names.contains("script") && names.contains("shell") {
    match (recipe_name, recipe_span) {
      (Some(recipe), Some(span)) =>
        raise ScriptAndShellAttributes(recipe~, span~)
      _ =>
        raise AttributeConflict(
          first="script",
          second="shell",
          span=attributes[0].span(),
        )
    }
  }
  if names.contains("exit-message") && names.contains("no-exit-message") {
    match (recipe_name, recipe_span) {
      (Some(recipe), Some(span)) => raise ExitMessageAttributes(recipe~, span~)
      _ =>
        raise AttributeConflict(
          first="exit-message",
          second="no-exit-message",
          span=attributes[0].span(),
        )
    }
  }
  groups.sort_by(attribute_lexical_compare)
  {
    names,
    platforms,
    private,
    doc,
    doc_expression,
    groups,
    working_directory,
    shell,
    script,
    script_interpreter,
    confirm,
    confirm_prompt,
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
  if self.platforms.is_empty() {
    return true
  }
  for expected in self.platforms {
    if (expected == Unix && platform.is_unix()) ||
      expected == platform.operating_system() {
      return true
    }
  }
  false
}

///|
pub fn platform_attributes_match(
  attributes : ArrayView[@syntax.Attribute],
  platform : TargetPlatform,
) -> Bool {
  let mut constrained = false
  for attribute in attributes {
    match platform_for(attribute.name()) {
      Some(Unix) => {
        constrained = true
        if platform.is_unix() {
          return true
        }
      }
      Some(expected) => {
        constrained = true
        if expected == platform.operating_system() {
          return true
        }
      }
      None => ()
    }
  }
  !constrained
}
