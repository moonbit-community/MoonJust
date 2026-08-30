///|
fn parser_command() -> @argparse.Command {
  let flags = command_flags()
  flags.append(other_flags())
  Command(
    "just",
    flags~,
    options=option_specs(),
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
    groups=[
      ArgGroup("command-mode", multiple=false, args=[
        "fmt", "init", "list", "show", "summary", "usage", "variables", "dump", "json",
        "evaluate", "groups", "choose", "changelog", "clean", "command", "edit",
        "man",
      ]),
    ],
  )
}

///|
fn command_kind(matches : @argparse.Matches) -> CommandKind {
  if matches.flags.get("check").unwrap_or(false) {
    return CheckCommand
  }
  if matches.flags.get("fmt").unwrap_or(false) {
    return FormatCommand
  }
  if matches.flags.get("init").unwrap_or(false) {
    return InitCommand
  }
  if matches.flags.get("list").unwrap_or(false) {
    return ListCommand
  }
  if matches.flags.get("show").unwrap_or(false) {
    return ShowCommand
  }
  if matches.flags.get("summary").unwrap_or(false) {
    return SummaryCommand
  }
  if matches.flags.get("usage").unwrap_or(false) {
    return UsageCommand
  }
  if matches.flags.get("variables").unwrap_or(false) {
    return VariablesCommand
  }
  if matches.flags.get("dump").unwrap_or(false) {
    return DumpCommand
  }
  if matches.flags.get("json").unwrap_or(false) {
    return JsonCommand
  }
  if matches.flags.get("evaluate").unwrap_or(false) {
    return EvaluateCommand
  }
  if matches.flags.get("groups").unwrap_or(false) {
    return GroupsCommand
  }
  if matches.flags.get("choose").unwrap_or(false) {
    return ChooseCommand
  }
  if matches.flags.get("changelog").unwrap_or(false) {
    return ChangelogCommand
  }
  if matches.flags.get("man").unwrap_or(false) {
    return ManCommand
  }
  if matches.flags.get("edit").unwrap_or(false) {
    return EditCommand
  }
  if matches.flags.get("clean").unwrap_or(false) {
    return CleanCommand
  }
  if matches.flags.get("command").unwrap_or(false) {
    return CommandCommand
  }
  RunCommand
}

///|
fn supported_option(token : String) -> Bool {
  match token {
    "--help"
    | "-h"
    | "--version"
    | "-V"
    | "--check"
    | "--fmt"
    | "--format"
    | "--init"
    | "--initialize"
    | "--list"
    | "-l"
    | "--show"
    | "-s"
    | "--summary"
    | "--usage"
    | "--variables"
    | "--dump"
    | "--json"
    | "--evaluate"
    | "--eval"
    | "--groups"
    | "--choose"
    | "--chooser"
    | "--edit"
    | "-e"
    | "--group"
    | "--list-submodules"
    | "--no-aliases"
    | "--unstable"
    | "--unsorted"
    | "-u"
    | "--list-heading"
    | "--list-prefix"
    | "--alias-style"
    | "--ceiling"
    | "--dump-format"
    | "--evaluate-format"
    | "--justfile"
    | "--justfile-name"
    | "-f"
    | "--dotenv-filename"
    | "-F"
    | "--dotenv-command"
    | "--dotenv-path"
    | "-E"
    | "--no-dotenv"
    | "--dry-run"
    | "-n"
    | "--quiet"
    | "-q"
    | "--time"
    | "--timestamp"
    | "--verbose"
    | "-v"
    | "--command-color"
    | "--timestamp-format"
    | "--color"
    | "--set"
    | "--shell"
    | "--shell-arg"
    | "--clear-shell-args"
    | "--allow-missing"
    | "--default-list"
    | "--explain"
    | "--global-justfile"
    | "-g"
    | "--highlight"
    | "--indentation"
    | "--no-highlight"
    | "--no-deps"
    | "--no-dependencies"
    | "--one"
    | "--shell-command"
    | "--tempdir"
    | "--working-directory"
    | "-d"
    | "--jobs"
    | "--no-cache"
    | "--yes"
    | "--clean"
    | "--changelog"
    | "--command"
    | "-c"
    | "--man" => true
    _ => false
  }
}

///|
fn option_name(token : String) -> String {
  let name = if token.has_prefix("--") {
    let builder = StringBuilder()
    for character in token {
      if character == '=' {
        break
      }
      builder.write_char(character)
    }
    builder.to_string()
  } else if token.has_prefix("-") && token.length() > 1 {
    token[:2].to_owned()
  } else {
    token
  }
  match name {
    "--format" => "--fmt"
    "--initialize" => "--init"
    "--eval" => "--evaluate"
    "--no-dependencies" => "--no-deps"
    _ => name
  }
}

///|
fn supported_value_option(name : String) -> Bool {
  match name {
    "--alias-style"
    | "--ceiling"
    | "--color"
    | "--command-color"
    | "--dump-format"
    | "--evaluate-format"
    | "--group"
    | "--indentation"
    | "--chooser"
    | "--justfile"
    | "--justfile-name"
    | "-f"
    | "--dotenv-filename"
    | "-F"
    | "--dotenv-command"
    | "--dotenv-path"
    | "-E"
    | "--list-heading"
    | "--list-prefix"
    | "--set"
    | "--shell"
    | "--shell-arg"
    | "--tempdir"
    | "--timestamp-format"
    | "--working-directory"
    | "-d"
    | "--jobs" => true
    _ => false
  }
}

///|
fn command_option(name : String) -> Bool {
  match name {
    "--help"
    | "-h"
    | "--version"
    | "-V"
    | "--check"
    | "--fmt"
    | "--init"
    | "--list"
    | "-l"
    | "--show"
    | "-s"
    | "--summary"
    | "--usage"
    | "--variables"
    | "--dump"
    | "--json"
    | "--evaluate"
    | "--groups"
    | "--choose"
    | "--edit"
    | "-e"
    | "--clean"
    | "--command"
    | "-c"
    | "--shell-command" => true
    _ => false
  }
}

///|
fn raw_command_option(name : String) -> Bool {
  name == "--command" || name == "-c" || name == "--shell-command"
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

///|
fn has_command_mode_before_invocation(argv : ArrayView[String]) -> Bool {
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
      if command_option(name) {
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
fn has_raw_command_mode_before_invocation(argv : ArrayView[String]) -> Bool {
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
      if raw_command_option(name) {
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
