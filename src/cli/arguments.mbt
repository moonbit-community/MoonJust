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
  ChooseCommand
  EditCommand
  CleanCommand
  CommandCommand
  ChangelogCommand
  ManCommand
} derive(Eq, Debug)

///|
/// Declarative CLI state after argparse has validated argv relationships.
pub struct CliArguments {
  command : CommandKind
  flags : Map[String, Bool]
  counts : Map[String, Int]
  values : Map[String, Array[String]]
  positional : Array[String]
  variable_overrides : Array[(String, String)]
  shell_arguments : Array[String]?
}

///|
pub fn CliArguments::command(self : CliArguments) -> CommandKind {
  self.command
}

///|
pub fn CliArguments::flag(self : CliArguments, name : String) -> Bool {
  self.flags.get(name).unwrap_or(false)
}

///|
pub fn CliArguments::count(self : CliArguments, name : String) -> Int {
  self.counts.get(name).unwrap_or(0)
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
/// Ordered `--set NAME VALUE` pairs. Repeated names remain present here so the
/// environment configuration layer can apply upstream last-wins semantics.
pub fn CliArguments::variable_overrides(
  self : CliArguments,
) -> ArrayView[(String, String)] {
  self.variable_overrides[:]
}

///|
/// Effective shell argument override. `None` means no CLI override, while an
/// empty array means `--clear-shell-args` won by command-line order.
pub fn CliArguments::shell_arguments(self : CliArguments) -> Array[String]? {
  self.shell_arguments.map(fn(arguments) { arguments.copy() })
}

///|
/// Preserve global configuration while turning one chooser line into a normal
/// recipe invocation. The caller receives a fresh positional array.
pub fn CliArguments::with_run_positionals(
  self : CliArguments,
  positional : Array[String],
) -> CliArguments {
  {
    command: RunCommand,
    flags: self.flags,
    counts: self.counts,
    values: self.values,
    positional: positional.copy(),
    variable_overrides: self.variable_overrides,
    shell_arguments: self.shell_arguments,
  }
}

///|
pub fn CliArguments::with_positionals(
  self : CliArguments,
  positional : Array[String],
) -> CliArguments {
  { ..self, positional: positional.copy(), }
}

///|
pub(all) suberror CliParseError {
  Invalid(String)
  Config(String)
  Unsupported(String)
} derive(Eq, Debug)

///|
fn flag(
  name : String,
  short? : Char,
  long? : String = name,
  about? : String = "",
  action? : @argparse.FlagAction = SetTrue,
  env? : StringView,
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
        env?,
        requires~,
        conflicts_with=conflicts,
      )
    None =>
      FlagArg(
        name,
        long~,
        about~,
        action~,
        env?,
        requires~,
        conflicts_with=conflicts,
      )
  }
}

///|
fn option(
  name : String,
  short? : Char,
  long? : String = name,
  about? : String = "",
  action? : @argparse.OptionAction = Set,
  env? : StringView,
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
        env?,
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
        env?,
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
      env="JUST_ALIAS_STYLE",
      defaults=["right"],
    ),
    option(
      "ceiling",
      long="ceiling",
      about="Stop justfile search above this directory",
      env="JUST_CEILING",
    ),
    option(
      "chooser",
      long="chooser",
      about="Override chooser binary",
      env="JUST_CHOOSER",
    ),
    option("color", long="color", about="Color mode", env="JUST_COLOR", defaults=[
      "auto",
    ]),
    option(
      "command-color",
      long="command-color",
      about="Recipe command color",
      env="JUST_COMMAND_COLOR",
    ),
    option("cygpath", long="cygpath", about="Path conversion binary", defaults=[
      "cygpath",
    ]),
    option(
      "dotenv-command",
      long="dotenv-command",
      about="Load environment from command",
      action=Append,
      env="JUST_DOTENV_COMMAND",
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
    option(
      "dump-format",
      long="dump-format",
      about="Dump format",
      env="JUST_DUMP_FORMAT",
      defaults=["just"],
    ),
    option(
      "evaluate-format",
      long="evaluate-format",
      about="Evaluate format",
      env="JUST_EVALUATE_FORMAT",
      defaults=["just"],
    ),
    option(
      "group",
      long="group",
      about="Only list recipes in group",
      action=Append,
      env="JUST_GROUP",
    ),
    option(
      "indentation",
      long="indentation",
      about="Recipe indentation",
      env="JUST_INDENTATION",
    ),
    option("jobs", long="jobs", about="Maximum parallel jobs", env="JUST_JOBS"),
    option(
      "justfile",
      short='f',
      long="justfile",
      about="Use justfile or - for stdin",
      env="JUST_JUSTFILE",
    ),
    option(
      "justfile-name",
      long="justfile-name",
      about="Search filename",
      env="JUST_JUSTFILE_NAME",
    ),
    option(
      "list-heading",
      long="list-heading",
      about="List heading",
      env="JUST_LIST_HEADING",
      defaults=["Available recipes:\n"],
    ),
    option(
      "list-prefix",
      long="list-prefix",
      about="List item prefix",
      env="JUST_LIST_PREFIX",
      defaults=["    "],
    ),
    option("shell", long="shell", about="Recipe shell"),
    option("shell-arg", long="shell-arg", about="Shell argument", action=Append),
    option("set", long="set", about="Override variable", action=Append),
    option(
      "tempdir",
      long="tempdir",
      about="Temporary directory",
      env="JUST_TEMPDIR",
    ),
    option(
      "timestamp-format",
      long="timestamp-format",
      about="Timestamp format",
      env="JUST_TIMESTAMP_FORMAT",
      defaults=["%H:%M:%S"],
    ),
    option(
      "working-directory",
      short='d',
      long="working-directory",
      about="Working directory",
      env="JUST_WORKING_DIRECTORY",
      requires=["justfile"],
    ),
  ]
}

///|
fn other_flags() -> Array[@argparse.FlagArg] {
  [
    flag(
      "allow-missing",
      about="Ignore missing recipe and module errors",
      env="JUST_ALLOW_MISSING",
    ),
    flag("clear-shell-args", about="Clear shell arguments"),
    flag(
      "default-list",
      about="List recipes with no arguments",
      env="JUST_DEFAULT_LIST",
    ),
    flag(
      "dry-run",
      short='n',
      about="Print commands without running",
      env="JUST_DRY_RUN",
      conflicts=["quiet"],
    ),
    flag(
      "explain",
      about="Print recipe docs before running",
      env="JUST_EXPLAIN",
    ),
    flag("global-justfile", short='g', about="Use global justfile", conflicts=[
      "justfile", "working-directory",
    ]),
    flag(
      "highlight",
      about="Highlight echoed recipe lines",
      env="JUST_HIGHLIGHT",
    ),
    flag(
      "list-submodules",
      about="List submodule recipes",
      env="JUST_LIST_SUBMODULES",
      requires=["list"],
    ),
    flag("no-aliases", about="Hide aliases", env="JUST_NO_ALIASES"),
    flag("no-cache", about="Bypass recipe cache", env="JUST_NO_CACHE"),
    flag(
      "no-deps",
      long="no-deps",
      about="Do not run dependencies",
      env="JUST_NO_DEPS",
    ),
    flag("no-dotenv", about="Do not load dotenv", env="JUST_NO_DOTENV"),
    flag(
      "no-highlight",
      about="Do not highlight commands",
      env="JUST_NO_HIGHLIGHT",
    ),
    flag("one", about="Allow only one recipe", env="JUST_ONE"),
    flag("quiet", short='q', about="Suppress output", env="JUST_QUIET", conflicts=[
      "dry-run",
    ]),
    flag("time", about="Print recipe timing", env="JUST_TIME"),
    flag("timestamp", about="Print command timestamps", env="JUST_TIMESTAMP"),
    flag("unsorted", short='u', about="Use source order", env="JUST_UNSORTED"),
    flag("unstable", about="Enable unstable features", env="JUST_UNSTABLE"),
    flag(
      "verbose",
      short='v',
      about="Verbose output",
      action=Count,
      env="JUST_VERBOSE",
    ),
    flag("yes", about="Automatically confirm recipes", env="JUST_YES"),
    flag("shell-command", about="Run command with recipe shell", requires=[
      "command",
    ]),
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
    return "error: the following required arguments were not provided:\n  --list <list>" +
      message.view(start_offset=list.length()).to_owned()
  }
  message
}

///|
/// Parse argv and environment using the pinned core argparse implementation.
pub fn parse_arguments(
  argv : ArrayView[String],
  env : Map[String, String],
) -> CliArguments raise CliParseError {
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
