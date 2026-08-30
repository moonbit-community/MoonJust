///|
/// Query commands keep accepting global options after their recipe/module
/// argument. Other command modes deliberately treat every following token as
/// command data, matching just's positional parsing rules.
fn has_interspersed_query_command(argv : ArrayView[String]) -> Bool {
  let mut consumes_value = false
  for token in argv {
    if consumes_value {
      consumes_value = false
      continue
    }
    if token == "--" {
      return false
    }
    if token.has_prefix("-") && token != "-" {
      let name = option_name(token)
      if name == "--show" || name == "-s" || name == "--list" || name == "-l" {
        return true
      }
      if supported_value_option(name) && !token.contains("=") {
        consumes_value = true
      }
    } else {
      return false
    }
  }
  false
}

///|
fn check_supported(argv : ArrayView[String]) -> Unit raise CliParseError {
  let mut consumes_value = false
  let mut after_separator = false
  let mut invocation_started = false
  for token in argv {
    if after_separator || invocation_started {
      continue
    }
    if consumes_value {
      consumes_value = false
      continue
    }
    if token == "--" {
      after_separator = true
      continue
    }
    if token.has_prefix("-") && token != "-" && token != "--" {
      let name = option_name(token)
      if !supported_option(name) {
        raise Unsupported(name)
      }
      if supported_value_option(name) && !token.contains("=") {
        consumes_value = true
      }
    } else {
      invocation_started = true
    }
  }
}

///|
fn normalize_argv(argv : ArrayView[String]) -> Array[String] {
  let mapped = argv.map(fn(token) {
    match token {
      "--format" => "--fmt"
      "--initialize" => "--init"
      "--eval" => "--evaluate"
      "--no-dependencies" => "--no-deps"
      _ => token
    }
  })
  let mut last_highlight : Int? = None
  for index, token in mapped {
    if token == "--highlight" || token == "--no-highlight" {
      last_highlight = Some(index)
    }
  }
  let result : Array[String] = []
  for index, token in mapped {
    if (token == "--highlight" || token == "--no-highlight") &&
      last_highlight != Some(index) {
      continue
    }
    result.push(token)
  }
  result
}

///|
priv struct EnvironmentArgv {
  argv : Array[String]
  variable_overrides : Array[(String, String)]
  shell_arguments : Array[String]?
}

///|
fn inline_option_value(token : String) -> String? {
  match token.find("=") {
    Some(index) => Some(token[index + 1:].to_owned())
    None => None
  }
}

///|
fn missing_value(option : String, expected : String) -> CliParseError {
  Invalid("error: '--\{option}' requires \{expected}")
}

///|
/// Core argparse options consume one value, while upstream `--set` consumes a
/// pair. Encode each pair as an opaque one-value option before parsing and keep
/// the actual values in a side table. The scan stops at recipe invocation so
/// recipe-local options with the same spelling remain untouched.
fn normalize_environment_argv(
  argv : ArrayView[String],
) -> EnvironmentArgv raise CliParseError {
  let command_mode = has_command_mode_before_invocation(argv)
  let raw_command_mode = has_raw_command_mode_before_invocation(argv)
  let normalized : Array[String] = []
  let variable_overrides : Array[(String, String)] = []
  let mut shell_arguments : Array[String]? = None
  let mut global = true
  let mut index = 0
  while index < argv.length() {
    let token = argv[index]
    if !global {
      normalized.push(token)
      index += 1
      continue
    }
    if token == "--" {
      normalized.push(token)
      global = false
      index += 1
      continue
    }
    if !token.has_prefix("-") || token == "-" {
      if !raw_command_mode && token != "-" {
        match token.find("=") {
          Some(separator) if separator > 0 => {
            variable_overrides.push(
              (token[:separator].to_owned(), token[separator + 1:].to_owned()),
            )
            normalized.push("--set=\{variable_overrides.length() - 1}")
            index += 1
            continue
          }
          _ => ()
        }
      }
      normalized.push(token)
      if !command_mode {
        global = false
      }
      index += 1
      continue
    }
    let name = option_name(token)
    if name == "--set" {
      let override_name = match inline_option_value(token) {
        Some(value) => value
        None =>
          match argv.get(index + 1) {
            Some(value) => {
              index += 1
              value
            }
            None => raise missing_value("set", "a VARIABLE and VALUE")
          }
      }
      let override_value = match argv.get(index + 1) {
        Some(value) => {
          index += 1
          value
        }
        None => raise missing_value("set", "a VARIABLE and VALUE")
      }
      variable_overrides.push((override_name, override_value))
      normalized.push("--set=\{variable_overrides.length() - 1}")
      index += 1
      continue
    }
    if name == "--clear-shell-args" {
      shell_arguments = Some([])
      normalized.push(token)
      index += 1
      continue
    }
    if name == "--shell-arg" {
      let value = match inline_option_value(token) {
        Some(value) => value
        None =>
          match argv.get(index + 1) {
            Some(value) => {
              normalized.push(token)
              normalized.push(value)
              index += 2
              value
            }
            None => raise missing_value("shell-arg", "a value")
          }
      }
      let arguments = shell_arguments.unwrap_or([])
      arguments.push(value)
      shell_arguments = Some(arguments)
      if token.contains("=") {
        normalized.push(token)
        index += 1
      }
      continue
    }
    normalized.push(token)
    if supported_value_option(name) && !token.contains("=") {
      match argv.get(index + 1) {
        Some(value) => {
          normalized.push(value)
          index += 2
        }
        None => index += 1
      }
    } else {
      index += 1
    }
  }
  { argv: normalized, variable_overrides, shell_arguments, }
}

///|
fn parser_argv(argv : ArrayView[String]) -> Array[String] {
  let result : Array[String] = []
  let query_mode = has_interspersed_query_command(argv)
  let mut consumes_value = false
  let mut separated = false
  for token in argv {
    if separated {
      result.push(token)
      continue
    }
    if consumes_value {
      result.push(token)
      consumes_value = false
      continue
    }
    if token == "--" {
      result.push(token)
      separated = true
      continue
    }
    let name = option_name(token)
    if token.has_prefix("-") && token != "-" && supported_option(name) {
      result.push(token)
      if supported_value_option(name) && !token.contains("=") {
        consumes_value = true
      }
      continue
    }
    if query_mode {
      result.push(token)
      continue
    }
    result.push("--")
    result.push(token)
    separated = true
  }
  result
}

///|
fn invocation_arguments(argv : ArrayView[String]) -> Array[String] {
  let result : Array[String] = []
  let mut invocation_started = false
  let mut consumes_global_value = false
  let mut after_global_separator = false
  for token in argv {
    if after_global_separator {
      result.push(token)
      invocation_started = true
      continue
    }
    if consumes_global_value {
      consumes_global_value = false
      continue
    }
    if token == "--" {
      if invocation_started {
        result.push(token)
      }
      after_global_separator = true
      continue
    }
    let name = option_name(token)
    if !invocation_started &&
      token.has_prefix("-") &&
      token != "-" &&
      supported_option(name) {
      if supported_value_option(name) && !token.contains("=") {
        consumes_global_value = true
      }
      continue
    }
    invocation_started = true
    result.push(token)
  }
  result
}

///|
fn validate_choice(
  matches : @argparse.Matches,
  name : String,
  choices : ArrayView[String],
) -> Unit raise CliParseError {
  guard matches.values.get(name) is Some(values) else { return }
  guard values.last() is Some(value) else { return }
  if !choices.contains(value) {
    raise Invalid(
      "error: invalid value '\{value}' for '--\{name}'; expected one of: " +
      choices.join(", "),
    )
  }
}

///|
fn enabled_environment_flag(value : String) -> Bool raise CliParseError {
  match value.trim().to_lower() {
    "1" | "true" | "yes" | "on" => true
    "0" | "false" | "no" | "off" | "" => false
    _ =>
      raise Invalid("error: invalid boolean value '\{value}' from environment")
  }
}

///|
fn enabled_unstable_environment(value : String) -> Bool {
  match value.trim().to_lower() {
    "0" | "false" | "no" | "off" | "" => false
    _ => true
  }
}

///|
fn check_unsupported_environment(
  env : Map[String, String],
) -> Unit raise CliParseError {
  for
    entry in [
      ("JUST_COMPLETE_ALIASES", "--complete-aliases", true),
      ("JUST_CYGPATH", "--cygpath", false),
    ] {
    let (name, option_name, is_flag) = entry
    guard env.get(name) is Some(value) else { continue }
    if !is_flag || enabled_environment_flag(value) {
      raise Unsupported(option_name)
    }
  }
}

///|
fn normalize_supported_environment(
  env : Map[String, String],
) -> Map[String, String] raise CliParseError {
  let normalized : Map[String, String] = Map([])
  for name, value in env {
    if name == "JUST_UNSTABLE" {
      if enabled_unstable_environment(value) {
        normalized[name] = "true"
      }
    } else if [
        "JUST_ALLOW_MISSING", "JUST_DEFAULT_LIST", "JUST_DRY_RUN", "JUST_EXPLAIN",
        "JUST_HIGHLIGHT", "JUST_LIST_SUBMODULES", "JUST_NO_ALIASES", "JUST_NO_CACHE",
        "JUST_NO_DEPS", "JUST_NO_DOTENV", "JUST_NO_HIGHLIGHT", "JUST_ONE", "JUST_QUIET",
        "JUST_TIME", "JUST_TIMESTAMP", "JUST_UNSORTED", "JUST_YES",
      ].contains(name) {
      if enabled_environment_flag(value) {
        normalized[name] = "true"
      }
    } else {
      normalized[name] = value
    }
  }
  normalized
}

///|
fn early_exit_requested(argv : ArrayView[String]) -> Bool {
  let command_mode = has_command_mode_before_invocation(argv)
  let mut consumes_value = false
  for token in argv {
    if consumes_value {
      consumes_value = false
      continue
    }
    if token == "--" {
      return false
    }
    if token.has_prefix("-") && token != "-" {
      let name = option_name(token)
      if name == "--help" || name == "-h" || name == "--version" || name == "-V" {
        return true
      }
      if supported_value_option(name) && !token.contains("=") {
        consumes_value = true
      }
    } else if !command_mode {
      return false
    }
  }
  false
}
