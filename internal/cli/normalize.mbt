///|
priv struct NormalizedArgv {
  command : ArgSpec?
  options : Array[String]
  positional : Array[String]
  variable_overrides : Array[(String, String)]
  shell_arguments : Array[String]?
  early_exit : Bool
  query_argument_conflict : Bool
  highlight : String?
}

///|
/// Split only a global option token. A short value option consumes the rest
/// of its cluster (e.g. -qfFILE), even when FILE looks like another flag.
fn option_occurrences(
  token : String,
) -> Array[(ArgSpec, String?)] raise CliParseError {
  if token.has_prefix("--") {
    let (name, inline) = match token.split_once("=") {
      Some((name, value)) => (name.to_owned(), Some(value.to_owned()))
      None => (token, None)
    }
    guard option_index.get(name) is Some(spec) else { raise Unsupported(name) }
    return [(spec, inline)]
  }
  let occurrences = []
  let chars = token[1:].iter()
  while chars.next() is Some(short) {
    let name = "-\{short}"
    guard option_index.get(name) is Some(spec) else { raise Unsupported(name) }
    if spec.action is (Value | Append | OverridePair) ||
      spec.operands is (External | QueryPath) {
      let rest = String::from_iter(chars)
      let inline = if rest.is_empty() {
        None
      } else {
        Some(rest.strip_prefix("=").unwrap_or(rest[:]).to_owned())
      }
      occurrences.push((spec, inline))
      break
    }
    occurrences.push((spec, None))
  }
  occurrences
}

///|
fn collect_positionals(
  tokens : ArrayView[String],
  positional : Array[String],
  overrides : Array[(String, String)],
) -> Unit {
  for i, token in tokens {
    if positional.is_empty() && token.find("=") is Some(split) && split > 0 {
      overrides.push((token[:split].to_owned(), token[split + 1:].to_owned()))
    } else {
      positional.append(tokens[i:])
      break
    }
  }
}

///|
/// Collect global options separately so core argparse never interprets a
/// recipe argument as an option. Each query option consumes its own path.
fn normalize_argv(
  argv : ArrayView[String],
) -> NormalizedArgv raise CliParseError {
  let options = []
  let positional : Array[String] = []
  let variable_overrides = []
  let mut shell_arguments : Array[String]? = None
  let mut highlight_index : Int32? = None
  let mut early_exit = false
  let positional_overrides = []
  let mut command : ArgSpec? = None
  let mut query_argument_conflict = false
  let mut index = 0
  while index < argv.length() {
    let token = argv[index]
    index += 1
    if command is Some({ operands: External, .. }) {
      positional.append(argv[index - 1:])
      break
    }
    if token == "--" {
      query_argument_conflict = command is Some({ operands: QueryPath, .. }) &&
        index < argv.length()
      positional.append(argv[index:])
      break
    }
    if !token.has_prefix("-") || token == "-" {
      if command is Some({ operands: QueryPath, .. }) {
        query_argument_conflict = true
        break
      }
      collect_positionals(argv[index - 1:], positional, positional_overrides)
      break
    }
    for (spec, inline) in option_occurrences(token) {
      let name = spec.name
      let spelling = "--" + name
      if spec.command is Some(_) {
        // --check refines --fmt regardless of their order on the command line.
        if !(command is Some({ command: Some(CheckCommand), .. })) {
          command = Some(spec)
        }
      }
      match spec.action {
        Flag | Count => {
          if spec.operands is QueryPath {
            options.push(spelling)
            match inline {
              Some(value) =>
                collect_positionals([value], positional, positional_overrides)
              None => {
                let start = index
                while argv.get(index) is Some(value) &&
                      (value == "-" || !value.has_prefix("-")) {
                  index += 1
                }
                if start == index && name == "show" {
                  raise missing_value(spec)
                }
                collect_positionals(
                  argv[start:index],
                  positional,
                  positional_overrides,
                )
              }
            }
            continue
          }
          if spec.operands is External {
            options.push(spelling)
            if inline is Some(value) {
              positional.push(value)
            }
            continue
          }
          if name == "help" || name == "version" {
            early_exit = true
          }
          if name == "highlight" || name == "no-highlight" {
            if highlight_index is Some(previous) {
              ignore(options.remove(previous))
            }
            highlight_index = Some(options.length())
          }
          if name == "clear-shell-args" {
            shell_arguments = Some([])
          }
          options.push(
            if inline is Some(value) {
              spelling + "=" + value
            } else {
              spelling
            },
          )
        }
        Value | Append | OverridePair => {
          if inline is None &&
            (name == "justfile-name" || name == "working-directory") {
            let next = argv.get(index)
            if next is None ||
              (next is Some(token) && token != "-" && token.has_prefix("-")) {
              if next is Some(token) && token != "--" {
                // Preserve unknown-option errors when the following token is not a value.
                ignore(option_occurrences(token))
              }
              raise missing_value(spec)
            }
          }
          let value = match inline {
            Some(value) => value
            None => {
              guard argv.get(index) is Some(value) else {
                if spec.action is OverridePair {
                  raise Invalid("error: '--set' requires a VARIABLE and VALUE")
                }
                if name == "shell-arg" {
                  raise Invalid("error: '--shell-arg' requires a value")
                }
                // Let argparse render its normal missing-value diagnostic.
                options.push(spelling)
                continue
              }
              index += 1
              value
            }
          }
          if spec.action is OverridePair {
            guard argv.get(index) is Some(override_value) else {
              raise Invalid("error: '--set' requires a VARIABLE and VALUE")
            }
            variable_overrides.push((value, override_value))
            index += 1
          } else if name == "shell-arg" {
            let arguments = shell_arguments.unwrap_or([])
            arguments.push(value)
            shell_arguments = Some(arguments)
          }
          options.push(spelling + "=" + value)
        }
      }
    }
  }
  variable_overrides.append(positional_overrides)
  {
    command,
    options,
    positional,
    variable_overrides,
    shell_arguments,
    early_exit,
    query_argument_conflict,
    highlight: highlight_index.map(i => options[i]),
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
  if env.get("JUST_COMPLETE_ALIASES") is Some(value) &&
    enabled_environment_flag(value) {
    raise Unsupported("--complete-aliases")
  }
}

///|
fn normalize_supported_environment(
  env : Map[String, String],
  normalized : NormalizedArgv,
) -> Map[String, String] raise CliParseError {
  let result : Map[String, String] = Map([])
  if normalized.early_exit {
    return result
  }
  for spec in argument_specs {
    guard spec.env is Some(name) && env.get(name) is Some(value) else {
      continue
    }
    if spec.action is Flag {
      let enabled = if spec.name == "unstable" {
        enabled_unstable_environment(value)
      } else {
        enabled_environment_flag(value)
      }
      if enabled {
        result[name] = "true"
      }
    } else {
      result[name] = value
    }
  }
  match normalized.highlight {
    Some("--highlight") => result.remove("JUST_NO_HIGHLIGHT")
    Some("--no-highlight") => result.remove("JUST_HIGHLIGHT")
    _ => ()
  }
  result
}
