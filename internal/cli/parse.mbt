///|
fn normalize_argparse_error(message : String) -> String {
  let fmt = "error: the following required argument was not provided: 'fmt' (required by 'check')"
  if message.has_prefix(fmt) {
    return (
      #|error: the following required arguments were not provided:
      #|  --fmt
      #|
      #|Usage: just --fmt --check --color <COLOR> [ARGUMENTS]...
      #|
      #|For more information, try '--help'.
    )
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
  if message.has_prefix(
      "error: conflicting arguments: dotenv-command and dotenv-filename",
    ) {
    (
      #|error: the argument '--dotenv-command <COMMAND>' cannot be used with '--dotenv-filename <DOTENV_FILENAME>'
      #|
      #|Usage: just --dotenv-command <COMMAND> --color <COLOR> [ARGUMENTS]...
      #|
      #|For more information, try '--help'.
    )
  } else if message.has_prefix(
      "error: conflicting arguments: dotenv-command and dotenv-path",
    ) {
    (
      #|error: the argument '--dotenv-command <COMMAND>' cannot be used with '--dotenv-path <DOTENV_PATH>'
      #|
      #|Usage: just --dotenv-command <COMMAND> --color <COLOR> [ARGUMENTS]...
      #|
      #|For more information, try '--help'.
    )
  } else if message.has_prefix(
      "error: conflicting arguments: dotenv-command and no-dotenv",
    ) {
    (
      #|error: the argument '--dotenv-command <COMMAND>' cannot be used with '--no-dotenv'
      #|
      #|Usage: just --dotenv-command <COMMAND> --color <COLOR> [ARGUMENTS]...
      #|
      #|For more information, try '--help'.
    )
  } else {
    message
  }
}

///|
fn parsed_jobs(matches : @argparse.Matches) -> Int32? raise CliParseError {
  guard matches.values.get("jobs") is Some([.., value]) else { return None }
  fn invalid(reason : String) -> CliParseError {
    Invalid(
      "error: invalid value '\{value}' for '--jobs <N>': \{reason}\n\nFor more information, try '--help'.",
    )
  }
  if value.is_empty() {
    raise invalid("cannot parse integer from empty string")
  }
  let digits = value.strip_prefix("+").unwrap_or(value[:])
  if digits.is_empty() || !digits.iter().all(c => c is ('0'..<='9')) {
    raise invalid("invalid digit found in string")
  }
  let parsed = @string.parse_int(digits, radix=10) catch {
    _ => raise invalid("number too large to fit in target type")
  }
  if parsed == 0 {
    raise invalid("number would be zero for non-zero type")
  }
  Some(parsed)
}

///|
fn unexpected_overrides(
  command : String,
  overrides : Array[(String, String)],
  positional : Array[String],
) -> CliParseError {
  let effective : Map[String, String] = Map([])
  for (name, value) in overrides {
    effective[name] = value
  }
  let names = effective.keys().collect()
  // just orders overrides by module path first, then by variable name.
  names.sort_by_key(name => {
    let path = name.split("::").map(part => part.to_owned()).collect()
    let variable = path.pop().unwrap()
    (path, variable)
  })
  let pairs = names.map(name => name + "=" + effective[name])
  let message = "error: " +
    @diagnostic.tick("--" + command) +
    " used with unexpected overrides: " +
    @diagnostic.join_list(pairs, "and", ticked=true)
  Config(
    if positional.is_empty() {
      message
    } else {
      message +
      "; and arguments: " +
      @diagnostic.join_list(positional, "and", ticked=true)
    },
  )
}

///|
/// Parse argv and environment using the pinned core argparse implementation.
pub fn parse_arguments(
  argv : ArrayView[String],
  env : Map[String, String],
) -> CliArguments raise CliParseError {
  let normalized = normalize_argv(argv)
  let normalized_env = normalize_supported_environment(env, normalized)
  let matches = parser_command.parse(
    argv=normalized.options,
    env=normalized_env,
  ) catch {
    error if error
      .to_string()
      .has_prefix(
        "error: argument '--working-directory' cannot be used multiple times",
      ) =>
      raise Invalid(
        "error: the argument '\{option_index["--working-directory"].usage()}' cannot be used multiple times\n\nUsage: just [OPTIONS] [ARGUMENTS]...\n\nFor more information, try '--help'.",
      )
    error if error
      .to_string()
      .has_prefix("error: conflicting arguments: global-justfile and ") =>
      raise search_conflict(normalized, env)
    error => raise Invalid(normalize_argparse_error(error.to_string()))
  }
  if normalized.query_argument_conflict && normalized.command is Some(spec) {
    raise conflict_error(
      spec,
      ["[ARGUMENTS]..."],
      supplied_specs(normalized, env),
    )
  }
  if !normalized.early_exit {
    check_unsupported_environment(env)
  }
  let command = normalized.command
    .bind(spec => spec.command)
    .unwrap_or(RunCommand)
  for spec in argument_specs {
    if !spec.requires_any.is_empty() &&
      matches.values.contains(spec.name) &&
      !spec.requires_any.any(name => matches.flags.get(name) == Some(true)) {
      let required = spec.requires_any.map(name => "'--" + name + "'")
      raise Invalid(
        "error: '--" + spec.name + "' requires " + required.join(" or "),
      )
    }
    if !spec.choices.is_empty() &&
      matches.values.get(spec.name) is Some([.., value]) &&
      !spec.choices.contains(value) {
      raise Invalid(
        "error: invalid value '\{value}' for '--\{spec.name}'; expected one of: " +
        spec.choices.join(", "),
      )
    }
  }
  let jobs = parsed_jobs(matches)
  let command_arguments = normalized.positional
  for (name, _) in normalized.variable_overrides {
    if !valid_override_path(name) {
      raise Config("error: invalid override path " + @diagnostic.tick(name))
    }
  }
  if (
      command == ListCommand ||
      command == ShowCommand ||
      command == UsageCommand
    ) &&
    !valid_query_module_path(command_arguments) {
    raise Config(
      "error: invalid module path `" + command_arguments.join(" ") + "`",
    )
  }
  if command == CommandCommand && command_arguments.is_empty() {
    raise Invalid(
      "error: a value is required for '--command <COMMAND>...' but none was supplied\n\nFor more information, try '--help'.",
    )
  }
  if !normalized.variable_overrides.is_empty() &&
    normalized.command is Some(spec) &&
    spec.operands is SearchOnly {
    let name = match command {
      CheckCommand | FormatCommand => "format"
      _ => spec.name
    }
    raise unexpected_overrides(
      name,
      normalized.variable_overrides,
      command_arguments,
    )
  }
  let values = matches.values
  if values.get("justfile-name") is Some(groups) {
    let filenames = []
    for group in groups {
      for name in group.split(",") {
        filenames.push(name.to_owned())
      }
    }
    values["justfile-name"] = filenames
  }
  if !command_arguments.is_empty() {
    values["arguments"] = command_arguments
  }
  if !normalized.variable_overrides.is_empty() {
    let flattened : Array[String] = []
    for entry in normalized.variable_overrides {
      flattened.push(entry.0)
      flattened.push(entry.1)
    }
    values["set"] = flattened
  }
  let flags = matches.flags
  match normalized.shell_arguments {
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
    jobs,
    positional: command_arguments,
    variable_overrides: normalized.variable_overrides,
    shell_arguments: normalized.shell_arguments,
  }
}

///|
pub fn render_help() -> String {
  parser_command.render_help()
}
