///|
/// A process failure for live execution. Child output has already been sent to
/// the configured `HostAsyncOutput` and is therefore intentionally not stored
/// for replay.
#derive(Debug)
pub(all) suberror LiveRuntimeError {
  LiveExecution(
    error~ : @planner.ExecutionError,
    commands~ : Int32,
    show_message~ : Bool,
  )
}

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
    ShellLaunchIo(recipe~, shell~, detail~)
  } else {
    ShellNotFound(recipe~, shell~, detail~)
  }
}

///|
#derive(Eq, Debug)
pub struct ExecutionSummary {
  commands : Int32
}

///|
pub fn ExecutionSummary::commands(self : ExecutionSummary) -> Int32 {
  self.commands
}

///|
fn live_failure(
  error : @planner.ExecutionError,
  commands : Int32,
  show_message~ : Bool = true,
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
pub fn LiveRuntimeError::commands(self : LiveRuntimeError) -> Int32 {
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
pub fn LiveRuntimeError::exit_code(self : LiveRuntimeError) -> Int32 {
  self.error().exit_code()
}

///|
priv enum LiveTaskOutcome {
  LiveCompleted(ExecutionSummary)
  LiveFailed(LiveRuntimeError)
  LiveBlocked
}
