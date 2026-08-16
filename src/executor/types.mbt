///|
/// Controls observable line execution behavior without granting host access.
pub struct ExecutionOptions {
  dry_run : Bool
  quiet : Bool
  echo_quiet : Bool
  verbose : Bool
  verbosity : Int
  time : Bool
  timestamp : String?
  command_color : CommandColor?
  jobs : Int
  cache_enabled : Bool
  unstable : Bool
  no_dependencies : Bool
  explain : Bool
  color_enabled : Bool
  guards : Bool
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
  {
    dry_run,
    quiet,
    echo_quiet: false,
    verbose,
    verbosity: if verbose {
      1
    } else {
      0
    },
    time,
    timestamp,
    command_color,
    jobs: 1,
    cache_enabled: true,
    unstable: false,
    no_dependencies: false,
    explain: false,
    color_enabled: command_color is Some(_),
    guards: false,
  }
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
  {
    dry_run,
    quiet,
    echo_quiet: false,
    verbose,
    verbosity: if verbose {
      1
    } else {
      0
    },
    time,
    timestamp,
    command_color,
    jobs: 1,
    cache_enabled: true,
    unstable: false,
    no_dependencies: false,
    explain: false,
    color_enabled: command_color is Some(_),
    guards: false,
  }
}

///|
/// Return a copy with the bounded scheduler width selected by the application.
pub fn ExecutionOptions::with_jobs(
  self : ExecutionOptions,
  jobs : Int,
) -> ExecutionOptions {
  { ..self, jobs, }
}

///|
/// Return a copy with recipe caching enabled or disabled.
pub fn ExecutionOptions::with_cache(
  self : ExecutionOptions,
  enabled : Bool,
) -> ExecutionOptions {
  { ..self, cache_enabled: enabled }
}

///|
pub fn ExecutionOptions::with_unstable(
  self : ExecutionOptions,
  enabled : Bool,
) -> ExecutionOptions {
  { ..self, unstable: enabled }
}

///|
/// Return a copy which omits both normal and subsequent recipe dependencies.
pub fn ExecutionOptions::with_no_dependencies(
  self : ExecutionOptions,
  enabled : Bool,
) -> ExecutionOptions {
  { ..self, no_dependencies: enabled }
}

///|
pub fn ExecutionOptions::with_explain(
  self : ExecutionOptions,
  enabled : Bool,
) -> ExecutionOptions {
  { ..self, explain: enabled }
}

///|
pub fn ExecutionOptions::with_color_enabled(
  self : ExecutionOptions,
  enabled : Bool,
) -> ExecutionOptions {
  { ..self, color_enabled: enabled }
}

///|
pub fn ExecutionOptions::with_guards(
  self : ExecutionOptions,
  enabled : Bool,
) -> ExecutionOptions {
  { ..self, guards: enabled }
}

///|
pub fn ExecutionOptions::with_quiet(
  self : ExecutionOptions,
  enabled : Bool,
) -> ExecutionOptions {
  { ..self, quiet: enabled }
}

///|
pub fn ExecutionOptions::with_echo_quiet(
  self : ExecutionOptions,
  enabled : Bool,
) -> ExecutionOptions {
  { ..self, echo_quiet: enabled }
}

///|
pub fn ExecutionOptions::with_verbosity(
  self : ExecutionOptions,
  verbosity : Int,
) -> ExecutionOptions {
  { ..self, verbose: verbosity > 0, verbosity }
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
pub fn ExecutionOptions::echo_quiet(self : ExecutionOptions) -> Bool {
  self.echo_quiet
}

///|
pub fn ExecutionOptions::verbose(self : ExecutionOptions) -> Bool {
  self.verbose
}

///|
pub fn ExecutionOptions::verbosity(self : ExecutionOptions) -> Int {
  self.verbosity
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
pub fn ExecutionOptions::jobs(self : ExecutionOptions) -> Int {
  self.jobs
}

///|
pub fn ExecutionOptions::cache_enabled(self : ExecutionOptions) -> Bool {
  self.cache_enabled
}

///|
pub fn ExecutionOptions::unstable(self : ExecutionOptions) -> Bool {
  self.unstable
}

///|
pub fn ExecutionOptions::no_dependencies(self : ExecutionOptions) -> Bool {
  self.no_dependencies
}

///|
pub fn ExecutionOptions::explain(self : ExecutionOptions) -> Bool {
  self.explain
}

///|
pub fn ExecutionOptions::color_enabled(self : ExecutionOptions) -> Bool {
  self.color_enabled
}

///|
pub fn ExecutionOptions::guards(self : ExecutionOptions) -> Bool {
  self.guards
}

///|
pub(all) enum CommandColor {
  Bold
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
pub struct CacheDirective {
  recipe : String
  body : String
  interpreter : String
  interpreter_arguments : Array[String]
  environment : Array[(String, String)]
  extension : String
  working_directory : @path.PathValue
  positional : Array[String]
  extra : String
  inputs : Array[String]
  outputs : Array[String]
} derive(Eq)

///|
/// Script bodies, arguments, and environment values may contain secrets.
pub impl Debug for CacheDirective with fn to_repr(self) {
  Repr::record({
    "recipe": Repr(self.recipe),
    "body_bytes": Repr(@utf8.encode(self.body).length()),
    "interpreter": Repr(self.interpreter),
    "interpreter_argument_count": Repr(self.interpreter_arguments.length()),
    "environment_keys": Repr(self.environment.map(fn(entry) { entry.0 })),
    "extension": Repr(self.extension),
    "working_directory": Repr(self.working_directory),
    "positional_count": Repr(self.positional.length()),
    "extra_bytes": Repr(@utf8.encode(self.extra).length()),
    "input_count": Repr(self.inputs.length()),
    "output_count": Repr(self.outputs.length()),
  })
}

///|
fn CacheDirective::new(
  recipe : String,
  body : String,
  interpreter : String,
  interpreter_arguments : Array[String],
  environment : Array[(String, String)],
  extension : String,
  working_directory : @path.PathValue,
  positional : Array[String],
  extra : String,
  inputs : Array[String],
  outputs : Array[String],
) -> CacheDirective {
  {
    recipe,
    body,
    interpreter,
    interpreter_arguments,
    environment,
    extension,
    working_directory,
    positional,
    extra,
    inputs,
    outputs,
  }
}

///|
pub fn CacheDirective::recipe(self : CacheDirective) -> String {
  self.recipe
}

///|
pub fn CacheDirective::body(self : CacheDirective) -> String {
  self.body
}

///|
pub fn CacheDirective::interpreter(self : CacheDirective) -> String {
  self.interpreter
}

///|
pub fn CacheDirective::interpreter_arguments(
  self : CacheDirective,
) -> ArrayView[String] {
  self.interpreter_arguments[:]
}

///|
pub fn CacheDirective::environment(
  self : CacheDirective,
) -> ArrayView[(String, String)] {
  self.environment[:]
}

///|
pub fn CacheDirective::extension(self : CacheDirective) -> String {
  self.extension
}

///|
pub fn CacheDirective::working_directory(
  self : CacheDirective,
) -> @path.PathValue {
  self.working_directory
}

///|
pub fn CacheDirective::positional(self : CacheDirective) -> ArrayView[String] {
  self.positional[:]
}

///|
pub fn CacheDirective::extra(self : CacheDirective) -> String {
  self.extra
}

///|
pub fn CacheDirective::inputs(self : CacheDirective) -> ArrayView[String] {
  self.inputs[:]
}

///|
pub fn CacheDirective::outputs(self : CacheDirective) -> ArrayView[String] {
  self.outputs[:]
}

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
  tasks : Array[ExecutionTask]
  cache_directory : @path.PathValue?
  confirmations : Array[ConfirmationRequest]
}

///|
/// A fully evaluated confirmation that must be accepted before any process is
/// started. Requests preserve upstream pre-order recipe traversal.
pub struct ConfirmationRequest {
  recipe : String
  prompt : String
  is_dependency : Bool
} derive(Eq, Debug)

///|
pub fn ConfirmationRequest::new(
  recipe : String,
  prompt : String,
  is_dependency : Bool,
) -> ConfirmationRequest {
  { recipe, prompt, is_dependency }
}

///|
pub fn ConfirmationRequest::recipe(self : ConfirmationRequest) -> String {
  self.recipe
}

///|
pub fn ConfirmationRequest::prompt(self : ConfirmationRequest) -> String {
  self.prompt
}

///|
pub fn ConfirmationRequest::is_dependency(self : ConfirmationRequest) -> Bool {
  self.is_dependency
}

///|
/// Return true only for the affirmative forms accepted by upstream just.
pub fn confirmation_answer_is_yes(answer : String) -> Bool {
  let normalized = answer.trim().to_lower()
  normalized == "y" || normalized == "yes"
}

///|
/// A recipe-level unit in the explicit execution DAG. Dependencies reference
/// task ids in the same plan and are always lower than the task id.
pub struct ExecutionTask {
  id : Int
  order : Int
  recipe : String
  steps : Array[PlannedStep]
  dependencies : Array[Int]
  cache : CacheDirective?
  print_exit_message : Bool
  preamble : Bytes
}

///|
pub impl Debug for ExecutionTask with fn to_repr(self) {
  Repr::record({
    "id": Repr(self.id),
    "order": Repr(self.order),
    "recipe": Repr(self.recipe),
    "step_count": Repr(self.steps.length()),
    "dependencies": Repr(self.dependencies),
    "cache_enabled": Repr(self.cache is Some(_)),
    "print_exit_message": Repr(self.print_exit_message),
    "preamble_bytes": Repr(self.preamble.length()),
  })
}

///|
fn ExecutionTask::new(
  id : Int,
  order : Int,
  recipe : String,
  steps : Array[PlannedStep],
  dependencies : ArrayView[Int],
  cache? : CacheDirective,
  print_exit_message? : Bool = true,
  preamble? : Bytes = b"",
) -> ExecutionTask {
  {
    id,
    order,
    recipe,
    steps,
    dependencies: dependencies.to_owned(),
    cache,
    print_exit_message,
    preamble,
  }
}

///|
pub fn ExecutionTask::id(self : ExecutionTask) -> Int {
  self.id
}

///|
pub fn ExecutionTask::order(self : ExecutionTask) -> Int {
  self.order
}

///|
pub fn ExecutionTask::recipe(self : ExecutionTask) -> String {
  self.recipe
}

///|
pub fn ExecutionTask::steps(self : ExecutionTask) -> ArrayView[PlannedStep] {
  self.steps[:]
}

///|
pub fn ExecutionTask::dependencies(self : ExecutionTask) -> ArrayView[Int] {
  self.dependencies[:]
}

///|
pub fn ExecutionTask::cache(self : ExecutionTask) -> CacheDirective? {
  self.cache
}

///|
pub fn ExecutionTask::print_exit_message(self : ExecutionTask) -> Bool {
  self.print_exit_message
}

///|
pub fn ExecutionTask::preamble(self : ExecutionTask) -> BytesView {
  self.preamble[:]
}

///|
fn ExecutionPlan::new(
  steps : Array[PlannedStep],
  commands : Array[PlannedCommand],
  stderr : Bytes,
  options : ExecutionOptions,
  tasks? : Array[ExecutionTask] = [],
  cache_directory? : @path.PathValue,
  confirmations? : Array[ConfirmationRequest] = [],
) -> ExecutionPlan {
  { steps, commands, stderr, options, tasks, cache_directory, confirmations }
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
pub fn ExecutionPlan::with_stderr_prefix(
  self : ExecutionPlan,
  prefix : BytesView,
) -> ExecutionPlan {
  let stderr : Array[Byte] = []
  for byte in prefix {
    stderr.push(byte)
  }
  for byte in self.stderr {
    stderr.push(byte)
  }
  {
    steps: self.steps,
    commands: self.commands,
    stderr: Bytes::from_array(stderr),
    options: self.options,
    tasks: self.tasks,
    cache_directory: self.cache_directory,
    confirmations: self.confirmations,
  }
}

///|
pub fn ExecutionPlan::options(self : ExecutionPlan) -> ExecutionOptions {
  self.options
}

///|
pub fn ExecutionPlan::tasks(self : ExecutionPlan) -> ArrayView[ExecutionTask] {
  self.tasks[:]
}

///|
pub fn ExecutionPlan::cache_directory(self : ExecutionPlan) -> @path.PathValue? {
  self.cache_directory
}

///|
pub fn ExecutionPlan::confirmations(
  self : ExecutionPlan,
) -> ArrayView[ConfirmationRequest] {
  self.confirmations[:]
}

///|
/// Combine independently planned module graphs into one runtime plan. Task ids
/// are rebased and each later graph is fenced behind the previous graph so CLI
/// invocation order remains stable even when `--jobs` permits parallel work
/// within a recipe graph.
pub fn combine_execution_plans(
  plans : ArrayView[ExecutionPlan],
) -> ExecutionPlan {
  if plans.is_empty() {
    return ExecutionPlan::new([], [], b"", ExecutionOptions::new())
  }
  let steps : Array[PlannedStep] = []
  let commands : Array[PlannedCommand] = []
  let stderr : Array[Byte] = []
  let tasks : Array[ExecutionTask] = []
  let confirmations : Array[ConfirmationRequest] = []
  let mut cache_directory : @path.PathValue? = None
  let mut previous_terminal : Int? = None
  for plan in plans {
    for step in plan.steps() {
      steps.push(step)
    }
    for command in plan.commands() {
      commands.push(command)
    }
    for byte in plan.stderr() {
      stderr.push(byte)
    }
    for confirmation in plan.confirmations() {
      confirmations.push(confirmation)
    }
    if cache_directory is None {
      cache_directory = plan.cache_directory()
    }
    let offset = tasks.length()
    for task in plan.tasks() {
      let dependencies = task
        .dependencies()
        .map(fn(dependency) { dependency + offset })
      if dependencies.is_empty() {
        match previous_terminal {
          Some(terminal) => dependencies.push(terminal)
          None => ()
        }
      }
      tasks.push(
        ExecutionTask::new(
          task.id() + offset,
          tasks.length(),
          task.recipe(),
          task.steps().to_owned(),
          dependencies,
          cache?=task.cache(),
          print_exit_message=task.print_exit_message(),
          preamble=task.preamble().to_owned(),
        ),
      )
    }
    if !plan.tasks().is_empty() {
      previous_terminal = Some(tasks.length() - 1)
    }
  }
  ExecutionPlan::new(
    steps,
    commands,
    Bytes::from_array(stderr),
    plans[0].options(),
    tasks~,
    cache_directory?,
    confirmations~,
  )
}

///|
pub impl Debug for ExecutionPlan with fn to_repr(self) {
  Repr::record({
    "command_count": Repr(self.commands.length()),
    "step_count": Repr(self.steps.length()),
    "stderr_bytes": Repr(self.stderr.length()),
    "task_count": Repr(self.tasks.length()),
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

///|
/// One requested recipe in an independently compiled project module.
pub struct ProjectRecipeRequest {
  module_path : @modulepath.ModulePath
  recipe : String
  arguments : Array[@value.Value]
} derive(Eq, Debug)

///|
pub fn ProjectRecipeRequest::new(
  module_path : @modulepath.ModulePath,
  recipe : String,
  arguments? : Array[@value.Value] = [],
) -> ProjectRecipeRequest {
  { module_path, recipe, arguments: arguments.copy() }
}

///|
pub fn ProjectRecipeRequest::module_path(
  self : ProjectRecipeRequest,
) -> @modulepath.ModulePath {
  self.module_path
}

///|
pub fn ProjectRecipeRequest::recipe(self : ProjectRecipeRequest) -> String {
  self.recipe
}

///|
pub fn ProjectRecipeRequest::arguments(
  self : ProjectRecipeRequest,
) -> ArrayView[@value.Value] {
  self.arguments[:]
}

///|
/// Runtime values owned by one project module during execution planning.
pub struct ProjectModuleRuntime {
  module_path : @modulepath.ModulePath
  global : @evaluator.Environment
  context : @evaluator.EvaluationContext
  shell : @environment.ShellConfiguration
  cwd : @path.PathValue
  process_environment : Array[(String, String)]
  configuration : ScriptConfiguration
} derive(Debug)

///|
pub fn ProjectModuleRuntime::new(
  module_path : @modulepath.ModulePath,
  global : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  process_environment : ArrayView[(String, String)],
  configuration : ScriptConfiguration,
) -> ProjectModuleRuntime {
  {
    module_path,
    global,
    context,
    shell,
    cwd,
    process_environment: process_environment.to_owned(),
    configuration,
  }
}

///|
pub fn ProjectModuleRuntime::module_path(
  self : ProjectModuleRuntime,
) -> @modulepath.ModulePath {
  self.module_path
}

///|
pub fn ProjectModuleRuntime::global(
  self : ProjectModuleRuntime,
) -> @evaluator.Environment {
  self.global
}

///|
pub fn ProjectModuleRuntime::context(
  self : ProjectModuleRuntime,
) -> @evaluator.EvaluationContext {
  self.context
}

///|
pub fn ProjectModuleRuntime::shell(
  self : ProjectModuleRuntime,
) -> @environment.ShellConfiguration {
  self.shell
}

///|
pub fn ProjectModuleRuntime::cwd(
  self : ProjectModuleRuntime,
) -> @path.PathValue {
  self.cwd
}

///|
pub fn ProjectModuleRuntime::process_environment(
  self : ProjectModuleRuntime,
) -> ArrayView[(String, String)] {
  self.process_environment[:]
}

///|
pub fn ProjectModuleRuntime::configuration(
  self : ProjectModuleRuntime,
) -> ScriptConfiguration {
  self.configuration
}
