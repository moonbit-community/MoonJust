///|
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
  { path, spec, }
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
  { recipe, prompt, is_dependency, }
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
  { steps, commands, stderr, options, tasks, cache_directory, confirmations, }
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
