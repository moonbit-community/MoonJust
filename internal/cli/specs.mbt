///|
priv enum ArgAction {
  Flag
  Count
  Value
  Append
  OverridePair
}

///|
/// How a command interprets operands after global option processing.
priv enum CommandOperands {
  SearchOnly
  Trailing
  QueryPath
  External
}

///|
/// Both argv normalization and core argparse consume this definition.
priv struct ArgSpec {
  name : String
  action : ArgAction
  short : Char?
  long_alias : String?
  command : CommandKind?
  operands : CommandOperands
  usage_suffix : String?
  requires_any : ArrayView[String]
  about : String
  env : String?
  defaults : ArrayView[String]
  choices : ArrayView[String]
  requires : ArrayView[String]
  conflicts : ArrayView[String]
}

///|
fn arg(
  name : String,
  action : ArgAction,
  short? : Char,
  long_alias? : String,
  command? : CommandKind,
  operands~ : CommandOperands = SearchOnly,
  usage_suffix? : String,
  requires_any~ : ArrayView[String] = [],
  about~ : String,
  env? : String,
  defaults~ : ArrayView[String] = [],
  choices~ : ArrayView[String] = [],
  requires~ : ArrayView[String] = [],
  conflicts~ : ArrayView[String] = [],
) -> ArgSpec {
  {
    name,
    action,
    short,
    long_alias,
    command,
    operands,
    usage_suffix,
    requires_any,
    about,
    env,
    defaults,
    choices,
    requires,
    conflicts,
  }
}

///|
let argument_specs : Array[ArgSpec] = [
  arg("help", Flag, short='h', about="Print help"),
  arg("version", Flag, short='V', about="Print version"),
  arg("check", Flag, command=CheckCommand, about="Check formatting", requires=[
    "fmt",
  ]),
  arg(
    "fmt",
    Flag,
    command=FormatCommand,
    long_alias="format",
    about="Format and overwrite justfile",
  ),
  arg(
    "init",
    Flag,
    command=InitCommand,
    long_alias="initialize",
    about="Initialize a new justfile",
  ),
  arg(
    "list",
    Flag,
    command=ListCommand,
    usage_suffix=" [<MODULE>...]",
    operands=QueryPath,
    short='l',
    about="List available recipes",
  ),
  arg(
    "show",
    Flag,
    command=ShowCommand,
    usage_suffix=" <RECIPE_PATH>...",
    operands=QueryPath,
    short='s',
    about="Show a recipe",
  ),
  arg("summary", Flag, command=SummaryCommand, about="List recipe names"),
  arg(
    "usage",
    Flag,
    command=UsageCommand,
    usage_suffix=" [<PATH>...]",
    operands=QueryPath,
    about="Print usage for a recipe, a module, or all root recipes",
  ),
  arg("variables", Flag, command=VariablesCommand, about="List variables"),
  arg("dump", Flag, command=DumpCommand, about="Print justfile"),
  arg("json", Flag, command=JsonCommand, about="Print justfile as JSON"),
  arg(
    "evaluate",
    Flag,
    command=EvaluateCommand,
    operands=Trailing,
    long_alias="eval",
    about="Evaluate variables",
  ),
  arg("groups", Flag, command=GroupsCommand, about="List recipe groups"),
  arg(
    "choose",
    Flag,
    command=ChooseCommand,
    operands=Trailing,
    about="Choose recipes",
  ),
  arg("changelog", Flag, command=ChangelogCommand, about="Print changelog"),
  arg(
    "clean",
    Flag,
    command=CleanCommand,
    usage_suffix=" [<RECIPE_PATH>...]",
    operands=QueryPath,
    about="Clear recipe cache",
  ),
  arg(
    "command",
    Flag,
    command=CommandCommand,
    usage_suffix=" <COMMAND>...",
    operands=External,
    short='c',
    about="Run an arbitrary command",
  ),
  arg("edit", Flag, command=EditCommand, short='e', about="Edit justfile"),
  arg("man", Flag, command=ManCommand, about="Print man page"),
  arg(
    "alias-style",
    Value,
    choices=["left", "right", "separate"],
    about="Set list alias display style",
    env="JUST_ALIAS_STYLE",
    defaults=["right"],
  ),
  arg(
    "ceiling",
    Value,
    about="Stop justfile search above this directory",
    env="JUST_CEILING",
  ),
  arg("chooser", Value, about="Override chooser binary", env="JUST_CHOOSER"),
  arg(
    "color",
    Value,
    choices=["always", "auto", "never"],
    about="Color mode",
    env="JUST_COLOR",
    defaults=["auto"],
  ),
  arg(
    "command-color",
    Value,
    choices=["black", "blue", "cyan", "green", "purple", "red", "yellow"],
    about="Recipe command color",
    env="JUST_COMMAND_COLOR",
  ),
  arg("cygpath", Value, env="JUST_CYGPATH", about="Path conversion binary", defaults=[
    "cygpath",
  ]),
  arg(
    "dotenv-command",
    Append,
    usage_suffix=" <COMMAND>",
    about="Load environment from command",
    env="JUST_DOTENV_COMMAND",
    conflicts=["dotenv-filename", "dotenv-path", "no-dotenv"],
  ),
  arg("dotenv-filename", Append, short='F', about="Environment filename", conflicts=[
    "dotenv-command", "dotenv-path",
  ]),
  arg("dotenv-path", Append, short='E', about="Environment path", conflicts=[
    "dotenv-command", "dotenv-filename",
  ]),
  arg(
    "dump-format",
    Value,
    usage_suffix=" <FORMAT>",
    choices=["json", "just"],
    about="Dump format",
    env="JUST_DUMP_FORMAT",
    defaults=["just"],
  ),
  arg(
    "evaluate-format",
    Value,
    usage_suffix=" <FORMAT>",
    choices=["just", "shell"],
    about="Evaluate format",
    env="JUST_EVALUATE_FORMAT",
    defaults=["just"],
  ),
  arg(
    "group",
    Append,
    requires_any=["list", "choose"],
    about="Only list recipes in group",
    env="JUST_GROUP",
  ),
  arg("indentation", Value, about="Recipe indentation", env="JUST_INDENTATION"),
  arg(
    "jobs",
    Value,
    usage_suffix=" <N>",
    about="Maximum parallel jobs",
    env="JUST_JOBS",
  ),
  arg(
    "justfile",
    Value,
    short='f',
    about="Use justfile or - for stdin",
    env="JUST_JUSTFILE",
  ),
  arg(
    "justfile-name",
    Append,
    usage_suffix=" <NAME>",
    about="Search for these filenames (repeatable, comma-separated)",
    env="JUST_JUSTFILE_NAME",
  ),
  arg(
    "list-heading",
    Value,
    usage_suffix=" <TEXT>",
    about="List heading",
    env="JUST_LIST_HEADING",
    defaults=["Available recipes:\n"],
  ),
  arg(
    "list-prefix",
    Value,
    usage_suffix=" <TEXT>",
    about="List item prefix",
    env="JUST_LIST_PREFIX",
    defaults=["    "],
  ),
  arg("shell", Value, about="Recipe shell"),
  arg("shell-arg", Append, about="Shell argument"),
  arg(
    "set",
    OverridePair,
    usage_suffix=" <VARIABLE> <VALUE>",
    about="Override variable",
  ),
  arg("tempdir", Value, about="Temporary directory", env="JUST_TEMPDIR"),
  arg(
    "timestamp-format",
    Value,
    about="Timestamp format",
    env="JUST_TIMESTAMP_FORMAT",
    defaults=["%H:%M:%S"],
  ),
  arg(
    "working-directory",
    Value,
    short='d',
    about="Set the working directory and start justfile discovery there",
    env="JUST_WORKING_DIRECTORY",
  ),
  arg(
    "allow-missing",
    Flag,
    about="Ignore missing recipe and module errors",
    env="JUST_ALLOW_MISSING",
  ),
  arg("clear-shell-args", Flag, about="Clear shell arguments"),
  arg(
    "default-list",
    Flag,
    about="List recipes with no arguments",
    env="JUST_DEFAULT_LIST",
  ),
  arg(
    "dry-run",
    Flag,
    short='n',
    about="Print commands without running",
    env="JUST_DRY_RUN",
    conflicts=["quiet"],
  ),
  arg(
    "explain",
    Flag,
    about="Print recipe docs before running",
    env="JUST_EXPLAIN",
  ),
  arg("global-justfile", Flag, short='g', about="Use global justfile", conflicts=[
    "justfile", "working-directory",
  ]),
  arg(
    "highlight",
    Flag,
    about="Highlight echoed recipe lines",
    env="JUST_HIGHLIGHT",
  ),
  arg(
    "list-submodules",
    Flag,
    about="List submodule recipes",
    env="JUST_LIST_SUBMODULES",
    requires=["list"],
  ),
  arg("no-aliases", Flag, about="Hide aliases", env="JUST_NO_ALIASES"),
  arg("no-cache", Flag, about="Bypass recipe cache", env="JUST_NO_CACHE"),
  arg(
    "no-deps",
    Flag,
    long_alias="no-dependencies",
    about="Do not run dependencies",
    env="JUST_NO_DEPS",
  ),
  arg("no-dotenv", Flag, about="Do not load dotenv", env="JUST_NO_DOTENV"),
  arg(
    "no-highlight",
    Flag,
    about="Do not highlight commands",
    env="JUST_NO_HIGHLIGHT",
  ),
  arg("one", Flag, about="Allow only one recipe", env="JUST_ONE"),
  arg("quiet", Flag, short='q', about="Suppress output", env="JUST_QUIET", conflicts=[
    "dry-run",
  ]),
  arg("time", Flag, about="Print recipe timing", env="JUST_TIME"),
  arg("timestamp", Flag, about="Print command timestamps", env="JUST_TIMESTAMP"),
  arg(
    "unsorted",
    Flag,
    short='u',
    about="Use source order",
    env="JUST_UNSORTED",
  ),
  arg("unstable", Flag, about="Enable unstable features", env="JUST_UNSTABLE"),
  arg("verbose", Count, short='v', about="Verbose output", env="JUST_VERBOSE"),
  arg("yes", Flag, about="Automatically confirm recipes", env="JUST_YES"),
  arg("shell-command", Flag, about="Run command with recipe shell", requires=[
    "command",
  ]),
]
