///|
let parser_command : @argparse.Command = {
  let flags : Array[@argparse.FlagArg] = []
  let options : Array[@argparse.OptionArg] = []
  let modes : Array[String] = []
  for spec in argument_specs {
    let env = spec.env.map(name => name[:])
    match spec.action {
      Flag | Count =>
        flags.push(
          FlagArg(
            spec.name,
            long=spec.name,
            short?=spec.short,
            about=spec.about,
            action=if spec.action is Count { Count } else { SetTrue },
            env?,
            requires=spec.requires,
            conflicts_with=spec.conflicts,
          ),
        )
      Value | Append | OverridePair =>
        options.push(
          OptionArg(
            spec.name,
            long=spec.name,
            short?=spec.short,
            about=spec.about,
            action=if spec.action is Value { Set } else { Append },
            env?,
            requires=spec.requires,
            conflicts_with=spec.conflicts,
            default_values=spec.defaults,
            allow_hyphen_values=true,
          ),
        )
    }
    if spec.command is Some(command) && command != CheckCommand {
      modes.push(spec.name)
    }
  }
  Command(
    "just",
    flags~,
    options~,
    positionals=[
      PositionArg(
        "arguments",
        num_args=ValueRange(lower=0),
        allow_hyphen_values=true,
      ),
    ],
    about="MoonJust: a just-compatible command runner implemented in MoonBit",
    disable_help_flag=true,
    disable_version_flag=true,
    groups=[ArgGroup("command-mode", multiple=false, args=modes)],
  )
}

///|
let option_index : Map[String, ArgSpec] = {
  let index = Map([])
  for spec in argument_specs {
    index["--" + spec.name] = spec
    if spec.short is Some(short) {
      index["-\{short}"] = spec
    }
    if spec.long_alias is Some(long_alias) {
      index["--" + long_alias] = spec
    }
  }
  index
}

///|
fn valid_override_component(component : StringView) -> Bool {
  if component.is_empty() {
    return false
  }
  let first = component.unsafe_get(0).to_int()
  if !((first >= 65 && first <= 90) ||
    (first >= 97 && first <= 122) ||
    first == 95) {
    return false
  }
  for index in 1..<component.length() {
    let code = component.unsafe_get(index).to_int()
    if !((code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      (code >= 48 && code <= 57) ||
      code == 95 ||
      code == 45) {
      return false
    }
  }
  true
}

///|
fn valid_override_path(path : String) -> Bool {
  if path.has_prefix(":") || path.has_suffix(":") || path.contains(":::") {
    return false
  }
  for component in path.split("::") {
    if !valid_override_component(component) {
      return false
    }
  }
  true
}

///|
fn valid_query_module_path(arguments : ArrayView[String]) -> Bool {
  for argument in arguments {
    if argument.contains("/") || argument == "." || argument == ".." {
      continue
    }
    for space_part in argument.split(" ") {
      if space_part.is_empty() {
        continue
      }
      for component in space_part.split("::") {
        if !valid_override_component(component) {
          return false
        }
      }
    }
  }
  true
}
