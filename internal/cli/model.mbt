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
