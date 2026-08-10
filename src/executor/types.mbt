///|
/// Controls observable line execution behavior without granting host access.
pub struct ExecutionOptions {
  dry_run : Bool
  quiet : Bool
  verbose : Bool
  time : Bool
  timestamp : String?
  command_color : CommandColor?
} derive(Eq, Debug)

///|
pub fn ExecutionOptions::new(
  dry_run? : Bool = false,
  quiet? : Bool = false,
  verbose? : Bool = false,
  time? : Bool = false,
  timestamp? : String,
  command_color? : CommandColor,
) -> ExecutionOptions {
  { dry_run, quiet, verbose, time, timestamp, command_color }
}

///|
pub fn ExecutionOptions::from_values(
  dry_run : Bool,
  quiet : Bool,
  verbose : Bool,
  time : Bool,
  timestamp : String?,
  command_color : CommandColor?,
) -> ExecutionOptions {
  { dry_run, quiet, verbose, time, timestamp, command_color }
}

///|
pub fn ExecutionOptions::dry_run(self : ExecutionOptions) -> Bool {
  self.dry_run
}

///|
pub fn ExecutionOptions::quiet(self : ExecutionOptions) -> Bool {
  self.quiet
}

///|
pub fn ExecutionOptions::verbose(self : ExecutionOptions) -> Bool {
  self.verbose
}

///|
pub fn ExecutionOptions::time(self : ExecutionOptions) -> Bool {
  self.time
}

///|
pub fn ExecutionOptions::timestamp(self : ExecutionOptions) -> String? {
  self.timestamp
}

///|
pub fn ExecutionOptions::command_color(
  self : ExecutionOptions,
) -> CommandColor? {
  self.command_color
}

///|
pub(all) enum CommandColor {
  Black
  Red
  Green
  Yellow
  Blue
  Magenta
  Cyan
  White
} derive(Eq, Debug)

///|
/// Interpreter and filesystem choices for one generated script.
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
  { interpreter, temporary_directory, extension, platform }
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
  { stdout, stderr, commands }
}

///|
/// One process step produced entirely before process capability is used.
pub struct PlannedCommand {
  spec : @host.CommandSpec
  recipe : String
  line : Int
  ignore_error : Bool
  echo : Bytes
} derive(Eq)

///|
fn PlannedCommand::new(
  spec : @host.CommandSpec,
  recipe : String,
  line : Int,
  ignore_error : Bool,
  echo? : Bytes = b"",
) -> PlannedCommand {
  { spec, recipe, line, ignore_error, echo }
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
  recipe_quiet : Bool
  line : Int
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
  recipe_quiet : Bool,
  line : Int,
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
    recipe_quiet,
    line,
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
pub fn PlannedLine::line(self : PlannedLine) -> Int {
  self.line
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
  quiet : Bool
} derive(Eq)

///|
fn PlannedScript::new(
  recipe : String,
  contents : Bytes,
  shebang : String?,
  cwd : @path.PathValue,
  environment : Array[(String, String)],
  configuration : ScriptConfiguration,
  quiet : Bool,
) -> PlannedScript {
  { recipe, contents, shebang, cwd, environment, configuration, quiet }
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
pub fn PlannedScript::quiet(self : PlannedScript) -> Bool {
  self.quiet
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
/// Runtime-owned temporary path and its exact process request.
pub struct MaterializedScript {
  path : @path.PathValue
  spec : @host.CommandSpec
}

///|
fn MaterializedScript::new(
  path : @path.PathValue,
  spec : @host.CommandSpec,
) -> MaterializedScript {
  { path, spec }
}

///|
pub fn MaterializedScript::path(self : MaterializedScript) -> @path.PathValue {
  self.path
}

///|
pub fn MaterializedScript::spec(self : MaterializedScript) -> @host.CommandSpec {
  self.spec
}

///|
pub struct ExecutionPlan {
  steps : Array[PlannedStep]
  commands : Array[PlannedCommand]
  stderr : Bytes
  options : ExecutionOptions
}

///|
fn ExecutionPlan::new(
  steps : Array[PlannedStep],
  commands : Array[PlannedCommand],
  stderr : Bytes,
  options : ExecutionOptions,
) -> ExecutionPlan {
  { steps, commands, stderr, options }
}

///|
pub fn ExecutionPlan::steps(self : ExecutionPlan) -> ArrayView[PlannedStep] {
  self.steps[:]
}

///|
pub fn ExecutionPlan::commands(
  self : ExecutionPlan,
) -> ArrayView[PlannedCommand] {
  self.commands[:]
}

///|
pub fn ExecutionPlan::stderr(self : ExecutionPlan) -> BytesView {
  self.stderr[:]
}

///|
pub fn ExecutionPlan::options(self : ExecutionPlan) -> ExecutionOptions {
  self.options
}

///|
pub impl Debug for ExecutionPlan with fn to_repr(self) {
  Repr::record({
    "command_count": Repr(self.commands.length()),
    "step_count": Repr(self.steps.length()),
    "stderr_bytes": Repr(self.stderr.length()),
  })
}

///|
pub fn ExecutionReport::stdout(self : ExecutionReport) -> BytesView {
  self.stdout[:]
}

///|
pub fn ExecutionReport::stderr(self : ExecutionReport) -> BytesView {
  self.stderr[:]
}

///|
pub fn ExecutionReport::commands(self : ExecutionReport) -> Int {
  self.commands
}

///|
/// Debug output reports byte counts because child output may contain secrets.
pub impl Debug for ExecutionReport with fn to_repr(self) {
  Repr::record({
    "stdout_bytes": Repr(self.stdout.length()),
    "stderr_bytes": Repr(self.stderr.length()),
    "commands": Repr(self.commands),
  })
}

///|
/// One requested root recipe and its already parsed positional values.
pub struct RecipeRequest {
  recipe : String
  arguments : Array[@value.Value]
} derive(Eq, Debug)

///|
pub fn RecipeRequest::new(
  recipe : String,
  arguments? : Array[@value.Value] = [],
) -> RecipeRequest {
  { recipe, arguments: arguments.copy() }
}

///|
pub fn RecipeRequest::recipe(self : RecipeRequest) -> String {
  self.recipe
}

///|
pub fn RecipeRequest::arguments(
  self : RecipeRequest,
) -> ArrayView[@value.Value] {
  self.arguments[:]
}
