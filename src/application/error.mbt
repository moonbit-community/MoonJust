///|
/// Failures raised while composing pure packages with explicit host input.
pub(all) suberror ApplicationError {
  Cli(@cli.CliParseError)
  Load(@loader.LoaderError)
  Format(@formatter.FormatterError)
  Evaluation(@evaluator.EvaluationError)
  Host(@host.HostError)
  Invocation(@invocation.InvocationError)
  Path(@path.PathError)
  Semantic(@semantic.SemanticError)
  AlreadyExists(@path.PathValue)
  Query(String)
  UnsupportedCommand(String)
} derive(Debug)

///|
pub fn ApplicationError::exit_code(self : ApplicationError) -> Int {
  match self {
    Cli(_) | UnsupportedCommand(_) => 2
    Load(_)
    | Format(_)
    | Evaluation(_)
    | Host(_)
    | Invocation(_)
    | Path(_)
    | Semantic(_)
    | AlreadyExists(_)
    | Query(_) => 1
  }
}

///|
pub fn ApplicationError::message(self : ApplicationError) -> String {
  match self {
    Cli(Invalid(message)) => message
    Cli(Unsupported(name)) => "error: option '\{name}' is not supported yet"
    Load(error) => "error[\{error.code()}]: \{error.message()}"
    Format(error) => "error[\{error.code()}]: \{error.message()}"
    Evaluation(error) => "error: evaluation failed: \{Repr(error)}"
    Host(error) => "error: host operation failed: \{Repr(error)}"
    Invocation(error) => "error: " + error.message()
    Path(error) => "error: invalid path: \{Repr(error)}"
    Semantic(error) => "error[\{error.code()}]: \{error.message()}"
    AlreadyExists(path) =>
      "error: justfile `\{path.as_string()}` already exists"
    Query(message) => "error: \{message}"
    UnsupportedCommand(name) => "error: command '\{name}' is not supported yet"
  }
}
