///|
/// Top-level commands exposed by the query-oriented CLI.
pub(all) enum CommandKind {
  RunCommand
  CheckCommand
  FormatCommand
  InitCommand
  ListCommand
  ShowCommand
  SummaryCommand
  UsageCommand
  VariablesCommand
  DumpCommand
  JsonCommand
  EvaluateCommand
  GroupsCommand
} derive(Eq, Debug)

///|
/// Declarative CLI state after argparse has validated argv relationships.
pub struct CliArguments {
  command : CommandKind
  flags : Map[String, Bool]
  values : Map[String, Array[String]]
  positional : Array[String]
} derive(Debug)

///|
pub fn CliArguments::command(self : CliArguments) -> CommandKind {
  self.command
}

///|
pub fn CliArguments::flag(self : CliArguments, name : String) -> Bool {
  self.flags.get(name).unwrap_or(false)
}

///|
pub fn CliArguments::value(self : CliArguments, name : String) -> String? {
  self.values.get(name).map(fn(values) { values.last().unwrap_or("") })
}

///|
pub fn CliArguments::values(
  self : CliArguments,
  name : String,
) -> ArrayView[String] {
  self.values.get(name).unwrap_or([])[:]
}

///|
pub fn CliArguments::positional(self : CliArguments) -> ArrayView[String] {
  self.positional[:]
}

///|
pub(all) suberror CliParseError {
  Invalid(String)
  Unsupported(String)
} derive(Eq, Debug)

///|
fn flag(
  name : String,
  short? : Char,
  long? : String = name,
  about? : String = "",
  action? : @argparse.FlagAction = SetTrue,
  requires? : ArrayView[String] = [],
  conflicts? : ArrayView[String] = [],
) -> @argparse.FlagArg {
  match short {
    Some(value) =>
      FlagArg(
        name,
        short=value,
        long~,
        about~,
        action~,
        requires~,
        conflicts_with=conflicts,
      )
    None =>
      FlagArg(name, long~, about~, action~, requires~, conflicts_with=conflicts)
  }
}

///|
fn option(
  name : String,
  short? : Char,
  long? : String = name,
  about? : String = "",
  action? : @argparse.OptionAction = Set,
  defaults? : ArrayView[String] = [],
  requires? : ArrayView[String] = [],
  conflicts? : ArrayView[String] = [],
) -> @argparse.OptionArg {
  match short {
    Some(value) =>
      OptionArg(
        name,
        short=value,
        long~,
        about~,
        action~,
        default_values=defaults,
        requires~,
        conflicts_with=conflicts,
        allow_hyphen_values=true,
      )
    None =>
      OptionArg(
        name,
        long~,
        about~,
        action~,
        default_values=defaults,
        requires~,
        conflicts_with=conflicts,
        allow_hyphen_values=true,
      )
  }
}

///|
fn command_flags() -> Array[@argparse.FlagArg] {
  [
    flag("help", short='h', about="Print help"),
    flag("version", short='V', about="Print version"),
    flag("check", about="Check formatting", requires=["fmt"]),
    flag("fmt", long="fmt", about="Format and overwrite justfile"),
    flag("init", long="init", about="Initialize a new justfile"),
    flag("list", short='l', about="List available recipes"),
    flag("show", short='s', about="Show a recipe"),
    flag("summary", about="List recipe names"),
    flag("usage", about="Print recipe usage"),
    flag("variables", about="List variables"),
    flag("dump", about="Print justfile"),
    flag("json", about="Print justfile as JSON"),
    flag("evaluate", about="Evaluate variables"),
    flag("groups", about="List recipe groups"),
    flag("choose", about="Choose recipes"),
    flag("changelog", about="Print changelog"),
    flag("clean", about="Clear recipe cache"),
    flag("command", short='c', about="Run an arbitrary command"),
    flag("completions", about="Print shell completion"),
    flag("edit", short='e', about="Edit justfile"),
    flag("man", about="Print man page"),
  ]
}

///|
fn option_specs() -> Array[@argparse.OptionArg] {
  [
    option(
      "alias-style",
      long="alias-style",
      about="Set list alias display style",
      defaults=["right"],
    ),
    option(
      "ceiling",
      long="ceiling",
      about="Stop justfile search above this directory",
    ),
    option("chooser", long="chooser", about="Override chooser binary"),
    option("color", long="color", about="Color mode", defaults=["auto"]),
    option("command-color", long="command-color", about="Recipe command color"),
    option("cygpath", long="cygpath", about="Path conversion binary", defaults=[
      "cygpath",
    ]),
    option(
      "dotenv-command",
      long="dotenv-command",
      about="Load environment from command",
      action=Append,
      conflicts=["dotenv-filename", "dotenv-path", "no-dotenv"],
    ),
    option(
      "dotenv-filename",
      short='F',
      long="dotenv-filename",
      about="Environment filename",
      action=Append,
      conflicts=["dotenv-command", "dotenv-path"],
    ),
    option(
      "dotenv-path",
      short='E',
      long="dotenv-path",
      about="Environment path",
      action=Append,
      conflicts=["dotenv-command", "dotenv-filename"],
    ),
    option("dump-format", long="dump-format", about="Dump format", defaults=[
      "just",
    ]),
    option("evaluate-format", long="evaluate-format", about="Evaluate format", defaults=[
      "just",
    ]),
    option(
      "group",
      long="group",
      about="Only list recipes in group",
      action=Append,
      requires=["list"],
    ),
    option("indentation", long="indentation", about="Recipe indentation"),
    option("jobs", long="jobs", about="Maximum parallel jobs"),
    option(
      "justfile",
      short='f',
      long="justfile",
      about="Use justfile or - for stdin",
    ),
    option("justfile-name", long="justfile-name", about="Search filename"),
    option("list-heading", long="list-heading", about="List heading", defaults=[
      "Available recipes:\n",
    ]),
    option("list-prefix", long="list-prefix", about="List item prefix", defaults=[
      "    ",
    ]),
    option("shell", long="shell", about="Recipe shell"),
    option("shell-arg", long="shell-arg", about="Shell argument", action=Append),
    option("set", long="set", about="Override variable"),
    option(
      "shell-command",
      long="shell-command",
      about="Run command with recipe shell",
    ),
    option("tempdir", long="tempdir", about="Temporary directory"),
    option(
      "timestamp-format",
      long="timestamp-format",
      about="Timestamp format",
      defaults=["%H:%M:%S"],
    ),
    option(
      "working-directory",
      short='d',
      long="working-directory",
      about="Working directory",
      requires=["justfile"],
    ),
  ]
}

///|
fn other_flags() -> Array[@argparse.FlagArg] {
  [
    flag("allow-missing", about="Ignore missing recipe and module errors"),
    flag("clear-shell-args", about="Clear shell arguments"),
    flag("default-list", about="List recipes with no arguments"),
    flag("dry-run", short='n', about="Print commands without running", conflicts=[
      "quiet",
    ]),
    flag("explain", about="Print recipe docs before running"),
    flag("global-justfile", short='g', about="Use global justfile"),
    flag("highlight", about="Highlight echoed recipe lines"),
    flag("list-submodules", about="List submodule recipes"),
    flag("no-aliases", about="Hide aliases"),
    flag("no-cache", about="Bypass recipe cache"),
    flag("no-deps", long="no-deps", about="Do not run dependencies"),
    flag(
      "no-dependencies",
      long="no-dependencies",
      about="Do not run dependencies",
    ),
    flag("no-dotenv", about="Do not load dotenv"),
    flag("no-highlight", about="Do not highlight commands"),
    flag("one", about="Allow only one recipe"),
    flag("quiet", short='q', about="Suppress output", conflicts=["dry-run"]),
    flag("time", about="Print recipe timing"),
    flag("timestamp", about="Print command timestamps"),
    flag("unsorted", short='u', about="Use source order"),
    flag("unstable", about="Enable unstable features"),
    flag("verbose", short='v', about="Verbose output", action=Count),
    flag("yes", about="Automatically confirm recipes"),
    flag("complete-aliases", about="Completion aliases"),
  ]
}

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
        "evaluate", "groups", "choose", "changelog", "clean", "command", "completions",
        "edit", "man",
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
    | "--group"
    | "--no-aliases"
    | "--unstable"
    | "--unsorted"
    | "-u"
    | "--list-heading"
    | "--list-prefix"
    | "--alias-style"
    | "--dump-format"
    | "--evaluate-format"
    | "--justfile"
    | "-f"
    | "--dotenv-command"
    | "--dotenv-filename"
    | "-F"
    | "--dotenv-path"
    | "-E"
    | "--no-dotenv"
    | "--dry-run"
    | "-n" => true
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
    _ => name
  }
}

///|
fn supported_value_option(name : String) -> Bool {
  match name {
    "--alias-style"
    | "--dump-format"
    | "--evaluate-format"
    | "--group"
    | "--justfile"
    | "-f"
    | "--dotenv-command"
    | "--dotenv-filename"
    | "-F"
    | "--dotenv-path"
    | "-E"
    | "--list-heading"
    | "--list-prefix" => true
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
    | "--groups" => true
    _ => false
  }
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
  argv.map(fn(token) {
    match token {
      "--format" => "--fmt"
      "--initialize" => "--init"
      "--eval" => "--evaluate"
      _ => token
    }
  })
}

///|
fn parser_argv(argv : ArrayView[String]) -> Array[String] {
  let result : Array[String] = []
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
/// Parse argv and environment using the pinned core argparse implementation.
pub fn parse_arguments(
  argv : ArrayView[String],
  env : Map[String, String],
) -> CliArguments raise CliParseError {
  check_supported(argv)
  let normalized = normalize_argv(argv)
  let parser_input = if has_command_mode_before_invocation(normalized) {
    normalized
  } else {
    parser_argv(normalized)
  }
  let matches = @argparse.Command::parse(
    parser_command(),
    argv=parser_input[:],
    env~,
  ) catch {
    error => raise Invalid(error.to_string())
  }
  validate_choice(matches, "alias-style", ["left", "right", "separate"])
  validate_choice(matches, "dump-format", ["json", "just"])
  validate_choice(matches, "evaluate-format", ["just", "shell"])
  let command = command_kind(matches)
  {
    command,
    flags: matches.flags,
    values: matches.values,
    positional: if command is RunCommand {
      invocation_arguments(normalized)
    } else {
      matches.values.get("arguments").unwrap_or([])
    },
  }
}

///|
pub fn render_help() -> String {
  parser_command().render_help()
}
