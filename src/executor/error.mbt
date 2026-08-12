///|
/// Failures produced while rendering or running one recipe line.
pub(all) suberror ExecutionError {
  Evaluation(@evaluator.EvaluationError)
  Host(@host.HostError)
  InvalidShebang(recipe~ : String, shebang~ : String)
  UnknownRecipe(recipe~ : String)
  DependencyCycle(stack~ : Array[String])
  CommandFailed(recipe~ : String, line~ : Int, exit_code~ : Int)
  CommandSignaled(recipe~ : String, line~ : Int, signal~ : @host.SignalKind)
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
    Evaluation(_)
    | Host(_)
    | InvalidShebang(..)
    | UnknownRecipe(_)
    | DependencyCycle(_) => 1
  }
}

///|
pub fn ExecutionError::message(self : ExecutionError) -> String {
  match self {
    Evaluation(error) => "error: recipe evaluation failed: \{Repr(error)}"
    Host(error) => "error: process operation failed: \{Repr(error)}"
    InvalidShebang(recipe~, shebang~) =>
      "error: recipe `\{recipe}` has invalid shebang `\{shebang}`"
    UnknownRecipe(recipe~) => "error: recipe `\{recipe}` does not exist"
    DependencyCycle(stack~) =>
      "error: recipe dependency cycle: " + stack.join(" -> ")
    CommandFailed(recipe~, line~, exit_code~) =>
      "error: recipe `\{recipe}` failed on line \{line} with exit code \{exit_code}"
    CommandSignaled(recipe~, line~, signal~) =>
      "error: recipe `\{recipe}` was terminated on line \{line} by \{Repr(signal)}"
  }
}
