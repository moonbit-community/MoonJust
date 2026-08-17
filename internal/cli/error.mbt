///|
/// Invalid states rejected by the CLI composition contract.
pub(all) suberror CliContractError {
  InvalidRecipeExitCode(Int)
  InvalidSignalNumber(Int)
} derive(Eq, Debug)

///|
/// Error stages retained until the application composition root.
pub(all) enum FailureKind {
  Usage
  Load
  Lex
  Parse
  Compile
  Invocation
  Evaluation
  Planning
  Host
  Capability
  RecipeExit(Int)
  SignalExit(Int)
  Internal
} derive(Eq, Debug)

///|
pub fn FailureKind::as_string(self : FailureKind) -> String {
  match self {
    Usage => "usage"
    Load => "load"
    Lex => "lex"
    Parse => "parse"
    Compile => "compile"
    Invocation => "invocation"
    Evaluation => "evaluation"
    Planning => "planning"
    Host => "host"
    Capability => "capability"
    RecipeExit(_) => "recipe-exit"
    SignalExit(_) => "signal-exit"
    Internal => "internal"
  }
}

///|
/// A typed application failure paired with its structured diagnostic.
pub struct ApplicationFailure {
  kind : FailureKind
  diagnostic : @diagnostic.Diagnostic
} derive(Debug)

///|
pub fn ApplicationFailure::new(
  kind : FailureKind,
  diagnostic : @diagnostic.Diagnostic,
) -> ApplicationFailure raise CliContractError {
  match kind {
    RecipeExit(0) => raise InvalidRecipeExitCode(0)
    SignalExit(signal) if signal < 1 || signal > 127 =>
      raise InvalidSignalNumber(signal)
    _ => { kind, diagnostic }
  }
}

///|
pub fn ApplicationFailure::kind(self : ApplicationFailure) -> FailureKind {
  self.kind
}

///|
pub fn ApplicationFailure::diagnostic(
  self : ApplicationFailure,
) -> @diagnostic.Diagnostic {
  self.diagnostic
}

///|
/// Map a failure to the exit status used by upstream `just` 1.57.0.
pub fn ApplicationFailure::exit_code(self : ApplicationFailure) -> Int {
  match self.kind {
    Usage => 2
    RecipeExit(code) => code
    SignalExit(signal) => 128 + signal
    Load
    | Lex
    | Parse
    | Compile
    | Invocation
    | Evaluation
    | Planning
    | Host
    | Capability
    | Internal => 1
  }
}
