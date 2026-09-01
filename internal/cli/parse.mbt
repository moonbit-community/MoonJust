///|
fn command_accepts_overrides(command : CommandKind) -> Bool {
  match command {
    RunCommand
    | ListCommand
    | ShowCommand
    | UsageCommand
    | EvaluateCommand
    | ChooseCommand
    | CommandCommand => true
    _ => false
  }
}

///|
fn normalize_argparse_error(message : String) -> String {
  let fmt = "error: the following required argument was not provided: 'fmt' (required by 'check')"
  if message.has_prefix(fmt) {
    return "error: the following required arguments were not provided:\n  --fmt" +
      message.view(start_offset=fmt.length()).to_owned()
  }
  let list = "error: the following required argument was not provided: 'list' (required by 'list-submodules')"
  if message.has_prefix(list) {
    return (
      #|error: the following required arguments were not provided:
      #|  --list [<MODULE>...]
      #|
      #|Usage: just --list [<MODULE>...] --list-submodules --color <COLOR> [ARGUMENTS]...
      #|
      #|For more information, try '--help'.
    )
  }
  message
}

///|
fn parse_explicit_file_fast_path(
  argv : ArrayView[String],
  env : Map[String, String],
) -> CliArguments? {
  guard argv.length() >= 3 && (argv[0] == "--justfile" || argv[0] == "-f") else {
    return None
  }
  for name, _ in env {
    if name.has_prefix("JUST_") {
      return None
    }
  }
  let mut command = RunCommand
  let flags : Map[String, Bool] = Map([])
  let positional : Array[String] = []
  if argv.length() == 3 && argv[2] == "--summary" {
    command = SummaryCommand
    flags["summary"] = true
  } else if argv.length() == 3 && argv[2] == "--fmt" {
    command = FormatCommand
    flags["fmt"] = true
  } else if argv.length() == 4 && argv[2] == "--fmt" && argv[3] == "--check" {
    command = CheckCommand
    flags["fmt"] = true
    flags["check"] = true
  } else if argv.length() >= 4 &&
    argv[2] == "--dry-run" &&
    !argv[3].has_prefix("-") &&
    !argv[3].contains("=") {
    flags["dry-run"] = true
    positional.append(argv[3:])
  } else if !argv[2].has_prefix("-") && !argv[2].contains("=") {
    positional.append(argv[2:])
  } else {
    return None
  }
  Some({
    command,
    flags,
    counts: Map([]),
    values: {
      "alias-style": ["right"],
      "color": ["auto"],
      "cygpath": ["cygpath"],
      "dump-format": ["just"],
      "evaluate-format": ["just"],
      "justfile": [argv[1]],
      "list-heading": ["Available recipes:\n"],
      "list-prefix": ["    "],
      "timestamp-format": ["%H:%M:%S"],
    },
    positional,
    variable_overrides: [],
    shell_arguments: None,
  })
}

///|
/// Parse argv and environment using the pinned core argparse implementation.
pub fn parse_arguments(
  argv : ArrayView[String],
  env : Map[String, String],
) -> CliArguments raise CliParseError {
  match parse_explicit_file_fast_path(argv, env) {
    Some(arguments) => return arguments
    None => ()
  }
  let normalized_env = if early_exit_requested(argv) {
    Map([])
  } else {
    normalize_supported_environment(env)
  }
  let environment_argv = normalize_environment_argv(argv)
  for entry in environment_argv.variable_overrides {
    if !valid_override_path(entry.0) {
      raise Config("error: invalid override path `" + entry.0 + "`")
    }
  }
  check_supported(environment_argv.argv)
  let normalized = normalize_argv(environment_argv.argv)
  for token in normalized {
    if token == "--highlight" {
      normalized_env.remove("JUST_NO_HIGHLIGHT")
    } else if token == "--no-highlight" {
      normalized_env.remove("JUST_HIGHLIGHT")
    }
  }
  let parser_input = parser_argv(normalized)
  let matches = @argparse.Command::parse(
    parser_command(),
    argv=parser_input[:],
    env=normalized_env,
  ) catch {
    error => raise Invalid(normalize_argparse_error(error.to_string()))
  }
  if !matches.flags.get("help").unwrap_or(false) &&
    !matches.flags.get("version").unwrap_or(false) {
    check_unsupported_environment(env)
  }
  validate_choice(matches, "alias-style", ["left", "right", "separate"])
  validate_choice(matches, "dump-format", ["json", "just"])
  validate_choice(matches, "evaluate-format", ["just", "shell"])
  validate_choice(matches, "color", ["always", "auto", "never"])
  validate_choice(matches, "command-color", [
    "black", "blue", "cyan", "green", "purple", "red", "yellow",
  ])
  match matches.values.get("jobs") {
    Some(values) =>
      match values.last() {
        Some(value) => {
          let parsed = @string.parse_int(value[:]) catch {
            _ =>
              raise Invalid(
                "error: invalid value '" +
                value +
                "' for '--jobs <N>': expected a positive integer\n\nFor more information, try '--help'.",
              )
          }
          if parsed <= 0 {
            raise Invalid(
              "error: invalid value '" +
              value +
              "' for '--jobs <N>': number would be zero for non-zero type\n\nFor more information, try '--help'.",
            )
          }
        }
        None => ()
      }
    None => ()
  }
  let command = command_kind(matches)
  let command_arguments = matches.values.get("arguments").unwrap_or([])
  if (command == ListCommand || command == ShowCommand) &&
    !valid_query_module_path(command_arguments) {
    raise Config(
      "error: invalid module path `" + command_arguments.join(" ") + "`",
    )
  }
  if command == CommandCommand &&
    matches.values.get("arguments").unwrap_or([]).is_empty() {
    raise Invalid(
      "error: a value is required for '--command <COMMAND>...' but none was supplied\n\nFor more information, try '--help'.",
    )
  }
  if !matches.values.get("group").unwrap_or([]).is_empty() &&
    command != ListCommand &&
    command != ChooseCommand {
    raise Invalid("error: '--group' requires '--list' or '--choose'")
  }
  if !environment_argv.variable_overrides.is_empty() &&
    !command_accepts_overrides(command) {
    raise Invalid(
      "error: '--set' cannot be used with command '\{Repr(command)}'",
    )
  }
  let values = matches.values
  if !environment_argv.variable_overrides.is_empty() {
    let flattened : Array[String] = []
    for entry in environment_argv.variable_overrides {
      flattened.push(entry.0)
      flattened.push(entry.1)
    }
    values["set"] = flattened
  }
  let flags = matches.flags
  match environment_argv.shell_arguments {
    Some(arguments) => {
      values["shell-arg"] = arguments.copy()
      flags["clear-shell-args"] = arguments.is_empty()
    }
    None => ()
  }
  {
    command,
    flags,
    counts: matches.flag_counts,
    values,
    positional: if command is RunCommand {
      invocation_arguments(normalized)
    } else {
      matches.values.get("arguments").unwrap_or([])
    },
    variable_overrides: environment_argv.variable_overrides,
    shell_arguments: environment_argv.shell_arguments,
  }
}

///|
pub fn render_help() -> String {
  parser_command().render_help()
}
