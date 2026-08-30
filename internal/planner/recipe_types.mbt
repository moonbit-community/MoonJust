///|
pub struct ScriptConfiguration {
  interpreter : @environment.ShellConfiguration
  temporary_directory : @path.PathValue
  extension : String?
  platform : @host.PlatformInfo
} derive(Eq, Debug)

///|
pub fn ScriptConfiguration::new(
  interpreter : @environment.ShellConfiguration,
  temporary_directory : @path.PathValue,
  platform : @host.PlatformInfo,
  extension? : String,
) -> ScriptConfiguration {
  { interpreter, temporary_directory, extension, platform, }
}

///|
pub fn ScriptConfiguration::interpreter(
  self : ScriptConfiguration,
) -> @environment.ShellConfiguration {
  self.interpreter
}

///|
pub fn ScriptConfiguration::temporary_directory(
  self : ScriptConfiguration,
) -> @path.PathValue {
  self.temporary_directory
}

///|
pub fn ScriptConfiguration::extension(self : ScriptConfiguration) -> String? {
  self.extension
}

///|
pub fn ScriptConfiguration::platform(
  self : ScriptConfiguration,
) -> @host.PlatformInfo {
  self.platform
}

///|
/// Captured bytes are kept separate by stream and retain process order.
pub struct ExecutionReport {
  stdout : Bytes
  stderr : Bytes
  commands : Int
} derive(Eq)

///|
pub fn ExecutionReport::new(
  stdout : Bytes,
  stderr : Bytes,
  commands : Int,
) -> ExecutionReport {
  { stdout, stderr, commands, }
}

///|
/// One process step produced entirely before process capability is used.
pub struct PlannedCommand {
  spec : @host.CommandSpec
  recipe : String
  line : Int
  ignore_error : Bool
  echo : Bytes
  is_guard : Bool
  continue_signals : Array[@host.SignalKind]
} derive(Eq)

///|
fn PlannedCommand::new(
  spec : @host.CommandSpec,
  recipe : String,
  line : Int,
  ignore_error : Bool,
  echo? : Bytes = b"",
  is_guard? : Bool = false,
  continue_signals? : ArrayView[@host.SignalKind] = [],
) -> PlannedCommand {
  {
    spec,
    recipe,
    line,
    ignore_error,
    echo,
    is_guard,
    continue_signals: continue_signals.to_owned(),
  }
}

///|
pub fn PlannedCommand::spec(self : PlannedCommand) -> @host.CommandSpec {
  self.spec
}

///|
pub fn PlannedCommand::recipe(self : PlannedCommand) -> String {
  self.recipe
}

///|
pub fn PlannedCommand::line(self : PlannedCommand) -> Int {
  self.line
}

///|
pub fn PlannedCommand::ignore_error(self : PlannedCommand) -> Bool {
  self.ignore_error
}

///|
pub fn PlannedCommand::is_guard(self : PlannedCommand) -> Bool {
  self.is_guard
}

///|
pub fn PlannedCommand::continue_signals(
  self : PlannedCommand,
) -> ArrayView[@host.SignalKind] {
  self.continue_signals[:]
}

///|
pub fn PlannedCommand::echo(self : PlannedCommand) -> BytesView {
  self.echo[:]
}

///|
pub impl Debug for PlannedCommand with fn to_repr(self) {
  Repr::record({
    "spec": Repr(self.spec),
    "recipe": Repr(self.recipe),
    "line": Repr(self.line),
    "ignore_error": Repr(self.ignore_error),
    "echo_bytes": Repr(self.echo.length()),
  })
}

///|
/// One ordinary line that must be evaluated immediately before it executes.
/// This preserves the observable ordering of backticks relative to prior lines.
pub struct PlannedLine {
  source : @syntax.RecipeLine
  environment : @evaluator.Environment
  context : @evaluator.EvaluationContext
  shell : @environment.ShellConfiguration
  cwd : @path.PathValue
  process_environment : Array[(String, String)]
  options : ExecutionOptions
  recipe : String
  positional : Array[String]
  recipe_quiet : Bool
  line : Int
  continue_signals : Array[@host.SignalKind]
}

///|
fn PlannedLine::new(
  source : @syntax.RecipeLine,
  environment : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  process_environment : Array[(String, String)],
  options : ExecutionOptions,
  recipe : String,
  positional? : ArrayView[String] = [],
  recipe_quiet : Bool,
  line : Int,
  continue_signals? : ArrayView[@host.SignalKind] = [],
) -> PlannedLine {
  {
    source,
    environment,
    context,
    shell,
    cwd,
    process_environment,
    options,
    recipe,
    positional: positional.to_owned(),
    recipe_quiet,
    line,
    continue_signals: continue_signals.to_owned(),
  }
}

///|
pub impl Debug for PlannedLine with fn to_repr(self) {
  Repr::record({
    "recipe": Repr(self.recipe),
    "line": Repr(self.line),
    "cwd": Repr(self.cwd),
    "environment_keys": Repr(
      self.process_environment.map(fn(entry) { entry.0 }),
    ),
  })
}

///|
pub fn PlannedLine::recipe(self : PlannedLine) -> String {
  self.recipe
}

///|
pub fn PlannedLine::positional(self : PlannedLine) -> ArrayView[String] {
  self.positional[:]
}

///|
pub fn PlannedLine::line(self : PlannedLine) -> Int {
  self.line
}

///|
pub fn PlannedLine::continue_signals(
  self : PlannedLine,
) -> ArrayView[@host.SignalKind] {
  self.continue_signals[:]
}

///|
/// Script contents are planned without filesystem effects. The runtime creates
/// the temporary file only when this step is reached.
pub struct PlannedScript {
  recipe : String
  contents : Bytes
  shebang : String?
  cwd : @path.PathValue
  environment : Array[(String, String)]
  configuration : ScriptConfiguration
  positional : Array[String]
  quiet : Bool
  continue_signals : Array[@host.SignalKind]
} derive(Eq)

///|
fn PlannedScript::new(
  recipe : String,
  contents : Bytes,
  shebang : String?,
  cwd : @path.PathValue,
  environment : Array[(String, String)],
  configuration : ScriptConfiguration,
  positional : ArrayView[String],
  quiet : Bool,
  continue_signals? : ArrayView[@host.SignalKind] = [],
) -> PlannedScript {
  {
    recipe,
    contents,
    shebang,
    cwd,
    environment,
    configuration,
    positional: positional.to_owned(),
    quiet,
    continue_signals: continue_signals.to_owned(),
  }
}

///|
pub fn PlannedScript::recipe(self : PlannedScript) -> String {
  self.recipe
}

///|
pub fn PlannedScript::contents(self : PlannedScript) -> BytesView {
  self.contents[:]
}

///|
pub fn PlannedScript::cwd(self : PlannedScript) -> @path.PathValue {
  self.cwd
}

///|
pub fn PlannedScript::environment(
  self : PlannedScript,
) -> ArrayView[(String, String)] {
  self.environment[:]
}

///|
pub fn PlannedScript::configuration(
  self : PlannedScript,
) -> ScriptConfiguration {
  self.configuration
}

///|
pub fn PlannedScript::positional(self : PlannedScript) -> ArrayView[String] {
  self.positional[:]
}

///|
pub fn PlannedScript::quiet(self : PlannedScript) -> Bool {
  self.quiet
}

///|
pub fn PlannedScript::continue_signals(
  self : PlannedScript,
) -> ArrayView[@host.SignalKind] {
  self.continue_signals[:]
}

///|
pub impl Debug for PlannedScript with fn to_repr(self) {
  Repr::record({
    "recipe": Repr(self.recipe),
    "content_bytes": Repr(self.contents.length()),
    "has_shebang": Repr(self.shebang is Some(_)),
    "cwd": Repr(self.cwd),
    "environment_keys": Repr(self.environment.map(fn(entry) { entry.0 })),
    "configuration": Repr(self.configuration),
    "positional_count": Repr(self.positional.length()),
    "quiet": Repr(self.quiet),
  })
}

///|
pub(all) enum PlannedStep {
  Command(PlannedCommand, Bytes)
  Script(PlannedScript, Bytes)
  Line(PlannedLine)
} derive(Debug)

///|
/// Evaluated cache contract attached only to script recipe tasks. Input file
/// digests are intentionally deferred until dependencies have completed.
