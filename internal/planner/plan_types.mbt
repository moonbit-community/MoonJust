///|
#derive(Eq)
pub struct CacheDirective {
  recipe : String
  body : String
  interpreter : String
  interpreter_arguments : Array[String]
  environment : Array[(String, String?)]
  extension : String
  working_directory : @path.PathValue
  positional : Array[String]
  extra : String
  inputs : Array[String]
  outputs : Array[String]
}

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
  environment : Array[(String, String?)],
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
) -> ArrayView[(String, String?)] {
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
  id : Int32
  order : Int32
  recipe : String
  steps : Array[PlannedStep]
  dependencies : Array[Int32]
  cache : CacheDirective?
  confirmation : (async () -> String raise ExecutionError)?
  timestamp : (async () -> String raise ExecutionError)?
  deferred_script : (
    String,
    async () -> (PlannedScript, Bytes, CacheDirective?) raise ExecutionError,
  )?
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
  id : Int32,
  order : Int32,
  recipe : String,
  steps : Array[PlannedStep],
  dependencies : ArrayView[Int32],
  cache? : CacheDirective,
  confirmation? : async () -> String raise ExecutionError,
  timestamp? : async () -> String raise ExecutionError,
  deferred_script? : (
    String,
    async () -> (PlannedScript, Bytes, CacheDirective?) raise ExecutionError,
  ),
  print_exit_message~ : Bool = true,
  preamble~ : Bytes = b"",
) -> ExecutionTask {
  {
    id,
    order,
    recipe,
    steps,
    dependencies: dependencies.to_owned(),
    cache,
    confirmation,
    timestamp,
    deferred_script,
    print_exit_message,
    preamble,
  }
}

///|
pub fn ExecutionTask::id(self : ExecutionTask) -> Int32 {
  self.id
}

///|
pub fn ExecutionTask::order(self : ExecutionTask) -> Int32 {
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
pub fn ExecutionTask::with_script(
  self : ExecutionTask,
  script : PlannedScript,
  echo : Bytes,
  cache : CacheDirective?,
) -> ExecutionTask {
  { ..self, steps: [Script(script, echo)], cache, deferred_script: None, }
}

///|
pub fn ExecutionTask::dependencies(self : ExecutionTask) -> ArrayView[Int32] {
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
  tasks~ : Array[ExecutionTask] = [],
  cache_directory? : @path.PathValue,
) -> ExecutionPlan {
  { steps, commands, stderr, options, tasks, cache_directory, }
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
pub impl Debug for ExecutionPlan with fn to_repr(self) {
  Repr::record({
    "command_count": Repr(self.commands.length()),
    "step_count": Repr(self.steps.length()),
    "stderr_bytes": Repr(self.stderr.length()),
    "task_count": Repr(self.tasks.length()),
  })
}

///|
/// One requested root recipe and its already parsed positional values.
