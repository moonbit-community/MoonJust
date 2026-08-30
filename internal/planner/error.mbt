///|
/// Failures produced while rendering or running one recipe line.
pub(all) suberror ExecutionError {
  Evaluation(@evaluator.EvaluationError)
  Invocation(@invocation.InvocationError)
  Host(@host.HostError)
  ShellNotFound(recipe~ : String, shell~ : String, detail~ : String)
  InvalidShebang(recipe~ : String, shebang~ : String)
  UnknownRecipe(recipe~ : String)
  DependencyCycle(stack~ : Array[String])
  CommandFailed(recipe~ : String, line~ : Int, exit_code~ : Int)
  CommandSignaled(recipe~ : String, line~ : Int, signal~ : @host.SignalKind)
  Interrupted(signal~ : @host.SignalKind)
  GuardCode(recipe~ : String, line~ : Int, code~ : Int)
  InvalidAttributeValue(message~ : String, span~ : @source.Span)
  CacheFailure(message~ : String)
} derive(Debug)

///|
pub fn ExecutionError::command_failed(
  recipe : String,
  line : Int,
  exit_code : Int,
) -> ExecutionError {
  CommandFailed(recipe~, line~, exit_code~)
}

///|
pub fn ExecutionError::command_signaled(
  recipe : String,
  line : Int,
  signal : @host.SignalKind,
) -> ExecutionError {
  CommandSignaled(recipe~, line~, signal~)
}

///|
pub fn ExecutionError::host(error : @host.HostError) -> ExecutionError {
  Host(error)
}

///|
pub fn ExecutionError::exit_code(self : ExecutionError) -> Int {
  match self {
    CommandFailed(exit_code~, ..) => exit_code
    CommandSignaled(signal~, ..) => signal.exit_code()
    Interrupted(signal~) => signal.exit_code()
    Evaluation(ProcessFailure(code~, ..)) => code
    Evaluation(BacktickFailure(code~, ..)) => code
    Evaluation(ProcessSignaled(signal~, ..)) => signal.exit_code()
    GuardCode(_) => 1
    Evaluation(_)
    | Invocation(_)
    | Host(_)
    | ShellNotFound(_)
    | InvalidShebang(..)
    | UnknownRecipe(_)
    | DependencyCycle(_)
    | InvalidAttributeValue(_)
    | CacheFailure(_) => 1
  }
}

///|
pub fn ExecutionError::message(self : ExecutionError) -> String {
  match self {
    Evaluation(error) => "error: recipe evaluation failed: \{Repr(error)}"
    Invocation(error) => "error: " + error.message()
    Host(error) => "error: process operation failed: \{Repr(error)}"
    ShellNotFound(recipe~, shell~, detail~) =>
      "error: recipe `" +
      recipe +
      "` could not be run because just could not find the shell `" +
      shell +
      "`: " +
      detail
    InvalidShebang(recipe~, shebang~) =>
      "error: recipe `\{recipe}` has invalid shebang `\{shebang}`"
    UnknownRecipe(recipe~) => "error: recipe `\{recipe}` does not exist"
    DependencyCycle(stack~) =>
      "error: recipe dependency cycle: " + stack.join(" -> ")
    CommandFailed(recipe~, line~, exit_code~) =>
      if line == 0 {
        "error: recipe `\{recipe}` failed with exit code \{exit_code}"
      } else {
        "error: recipe `\{recipe}` failed on line \{line} with exit code \{exit_code}"
      }
    CommandSignaled(recipe~, line~, signal~) =>
      if line == 0 {
        "error: recipe `\{recipe}` was terminated by signal \{signal.number()}"
      } else {
        "error: recipe `\{recipe}` was terminated on line \{line} by signal \{signal.number()}"
      }
    Interrupted(signal~) => "error: interrupted by " + signal.name()
    GuardCode(recipe~, line~, code~) =>
      "error: guard line in recipe `\{recipe}` on line \{line} returned reserved exit code \{code}"
    InvalidAttributeValue(message~, ..) => "error: " + message
    CacheFailure(message~) => "error: " + message
  }
}

///|
pub fn ExecutionError::to_diagnostic(
  self : ExecutionError,
) -> @diagnostic.Diagnostic? raise @diagnostic.DiagnosticError {
  match self {
    Evaluation(error) => Some(error.to_diagnostic())
    Invocation(error) => error.to_diagnostic()
    InvalidAttributeValue(message~, span~) =>
      Some(
        @diagnostic.Diagnostic::new("MJ-EXEC-0001", Error, message, span, ""),
      )
    CacheFailure(_) => None
    _ => None
  }
}
