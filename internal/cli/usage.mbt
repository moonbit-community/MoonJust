///|
fn ArgSpec::usage(self : ArgSpec) -> String {
  let suffix = match (self.usage_suffix, self.action) {
    (Some(suffix), _) => suffix
    (None, Count) => "..."
    (None, Flag) => ""
    (None, _) => " <" + self.name.replace_all(old="-", new="_").to_upper() + ">"
  }
  "--" + self.name + suffix
}

///|
fn missing_value(spec : ArgSpec) -> CliParseError {
  Invalid(
    "error: a value is required for '\{spec.usage()}' but none was supplied\n\nFor more information, try '--help'.",
  )
}

///|
/// Clap prints explicit argv in occurrence order, followed by options supplied
/// by the environment in declaration order. Its implicit defaults are omitted.
fn supplied_specs(
  normalized : NormalizedArgv,
  env : Map[String, String],
) -> Array[ArgSpec] {
  let specs = []
  let seen : Set[String] = Set([])
  for token in normalized.options {
    let spelling = token
      .split_once("=")
      .map(pair => pair.0.to_owned())
      .unwrap_or(token)
    let spec = option_index[spelling]
    if !seen.contains(spec.name) {
      seen.add(spec.name)
      specs.push(spec)
    }
  }
  let from_env = argument_specs.filter(spec => {
    spec.env is Some(name) && env.contains(name) && !seen.contains(spec.name)
  })
  from_env.sort_by_key(spec => spec.name)
  specs.append(from_env)
  specs
}

///|
fn conflict_error(
  first : ArgSpec,
  others : ArrayView[String],
  usage : ArrayView[ArgSpec],
) -> CliParseError {
  let detail = if others.length() == 1 {
    " '" + others[0] + "'"
  } else {
    ":\n  " + others.join("\n  ")
  }
  Invalid(
    "error: the argument '\{first.usage()}' cannot be used with" +
    detail +
    "\n\nUsage: just " +
    usage.map(spec => spec.usage()).join(" ") +
    " [ARGUMENTS]...\n\nFor more information, try '--help'.",
  )
}

///|
fn search_conflict(
  normalized : NormalizedArgv,
  env : Map[String, String],
) -> CliParseError {
  let specs = supplied_specs(normalized, env)
  let search = specs.filter(spec => {
    spec.name is ("global-justfile" | "justfile" | "working-directory")
  })
  let first = search[0]
  let conflicts = if first.name == "global-justfile" {
    search[1:].to_owned()
  } else {
    [option_index["--global-justfile"]]
  }
  let names = conflicts.map(spec => spec.name)
  conflict_error(
    first,
    conflicts.map(spec => spec.usage()),
    specs.filter(spec => !names.contains(spec.name)),
  )
}
