///|
/// A process failure retains all output emitted by completed steps so the CLI
/// can report the same command echoes and child streams before the diagnostic.
pub(all) suberror RuntimeError {
  Execution(
    error~ : @planner.ExecutionError,
    stdout~ : Bytes,
    stderr~ : Bytes,
    commands~ : Int
  )
} derive(Debug)

///|
/// A process failure for live execution. Child output has already been sent to
/// the configured `HostAsyncOutput` and is therefore intentionally not stored
/// for replay.
pub(all) suberror LiveRuntimeError {
  LiveExecution(
    error~ : @planner.ExecutionError,
    commands~ : Int,
    show_message~ : Bool
  )
} derive(Debug)

///|
fn process_error_detail(error : @host.HostError) -> String {
  match error {
    InvalidInput(detail) => detail
    PermissionDenied(_, detail~) => detail
    NotFound(path) => "No such file or directory: " + path.as_string()
    AlreadyExists(path) => "already exists: " + path.as_string()
    CapabilityDenied(capability) =>
      "capability denied: " + Repr(capability).to_string()
    CapabilityUnavailable(capability) =>
      "capability unavailable: " + Repr(capability).to_string()
    UnexpectedProcess(_) | ProcessMismatch(_) => "unexpected process invocation"
    RandomExhausted(_) => "host randomness unavailable"
  }
}

///|
fn shell_launch_error(
  recipe : String,
  shell : String,
  error : @host.HostError,
) -> @planner.ExecutionError {
  let detail = process_error_detail(error)
  if detail.to_lower().contains("directory name is invalid") {
    @planner.ShellLaunchIo(recipe~, shell~, detail~)
  } else {
    @planner.ShellNotFound(recipe~, shell~, detail~)
  }
}

///|
pub struct ExecutionSummary {
  commands : Int
} derive(Eq, Debug)

///|
pub fn ExecutionSummary::commands(self : ExecutionSummary) -> Int {
  self.commands
}

///|
fn live_failure(
  error : @planner.ExecutionError,
  commands : Int,
  show_message? : Bool = true,
) -> LiveRuntimeError {
  LiveExecution(error~, commands~, show_message~)
}

///|
pub fn LiveRuntimeError::error(
  self : LiveRuntimeError,
) -> @planner.ExecutionError {
  match self {
    LiveExecution(error~, ..) => error
  }
}

///|
pub fn LiveRuntimeError::commands(self : LiveRuntimeError) -> Int {
  match self {
    LiveExecution(commands~, ..) => commands
  }
}

///|
pub fn LiveRuntimeError::show_message(self : LiveRuntimeError) -> Bool {
  match self {
    LiveExecution(show_message~, ..) => show_message
  }
}

///|
fn LiveRuntimeError::with_recipe_exit_message(
  self : LiveRuntimeError,
  show_message : Bool,
) -> LiveRuntimeError {
  match self.error() {
    CommandFailed(..) | CommandSignaled(..) =>
      live_failure(self.error(), self.commands(), show_message~)
    _ => self
  }
}

///|
pub fn LiveRuntimeError::message(self : LiveRuntimeError) -> String {
  self.error().message()
}

///|
pub fn LiveRuntimeError::exit_code(self : LiveRuntimeError) -> Int {
  self.error().exit_code()
}

///|
fn runtime_failure(
  error : @planner.ExecutionError,
  stdout : Array[Byte],
  stderr : Array[Byte],
  commands : Int,
) -> RuntimeError {
  Execution(
    error~,
    stdout=Bytes::from_array(stdout.copy()),
    stderr=Bytes::from_array(stderr.copy()),
    commands~,
  )
}

///|
pub fn RuntimeError::error(self : RuntimeError) -> @planner.ExecutionError {
  match self {
    Execution(error~, ..) => error
  }
}

///|
pub fn RuntimeError::stdout(self : RuntimeError) -> BytesView {
  match self {
    Execution(stdout~, ..) => stdout[:]
  }
}

///|
pub fn RuntimeError::stderr(self : RuntimeError) -> BytesView {
  match self {
    Execution(stderr~, ..) => stderr[:]
  }
}

///|
pub fn RuntimeError::commands(self : RuntimeError) -> Int {
  match self {
    Execution(commands~, ..) => commands
  }
}

///|
pub fn RuntimeError::message(self : RuntimeError) -> String {
  self.error().message()
}

///|
pub fn RuntimeError::exit_code(self : RuntimeError) -> Int {
  self.error().exit_code()
}

///|
priv enum TaskOutcome {
  Completed(@planner.ExecutionReport)
  Failed(RuntimeError)
  Blocked
}

///|
priv enum LiveTaskOutcome {
  LiveCompleted(ExecutionSummary)
  LiveFailed(LiveRuntimeError)
  LiveBlocked
}
