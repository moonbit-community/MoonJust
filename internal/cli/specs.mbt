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
