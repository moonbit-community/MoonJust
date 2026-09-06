///|
pub(all) suberror EvaluationError {
  Parse(@parser.ParserError)
  UndefinedVariable(name~ : String, span~ : @source.Span)
  VariableCycle(name~ : String, stack~ : Array[String], span~ : @source.Span)
  TypeMismatch(expected~ : String, actual~ : String, span~ : @source.Span)
  Builtin(@builtin.BuiltinError, span~ : @source.Span)
  EffectRequired(effect~ : String, span~ : @source.Span)
  Host(@host.HostError, span~ : @source.Span)
  ProcessFailure(code~ : Int, span~ : @source.Span)
  BacktickFailure(code~ : Int, span~ : @source.Span)
  ProcessSignaled(signal~ : @host.SignalKind, span~ : @source.Span)
  InvalidUtf8(span~ : @source.Span)
  RecursionLimitExceeded(limit~ : Int, span~ : @source.Span)
  FunctionRecursionLimit(name~ : String, limit~ : Int, span~ : @source.Span)
  NodeLimitExceeded(limit~ : Int, span~ : @source.Span)
  OutputLimitExceeded(limit~ : Int, span~ : @source.Span)
  MissingContext(fact~ : String, span~ : @source.Span)
  ArgumentCount(
    recipe~ : String,
    expected~ : String,
    actual~ : Int,
    span~ : @source.Span
  )
  UnknownOverrides(names~ : Array[String], span~ : @source.Span)
  FunctionArgumentCount(
    name~ : String,
    expected~ : Int,
    actual~ : Int,
    span~ : @source.Span
  )
  EmptyParameter(recipe~ : String, parameter~ : String, span~ : @source.Span)
} derive(Eq, Debug)

///|
pub fn EvaluationError::code(self : EvaluationError) -> String {
  match self {
    Parse(_) => "MJ-EVAL-0000"
    UndefinedVariable(_) => "MJ-EVAL-0001"
    VariableCycle(_) => "MJ-EVAL-0002"
    TypeMismatch(_) => "MJ-EVAL-0003"
    Builtin(_) => "MJ-EVAL-0004"
    EffectRequired(_) => "MJ-EVAL-0005"
    Host(_) => "MJ-EVAL-0006"
    ProcessFailure(_) => "MJ-EVAL-0007"
    BacktickFailure(_) => "MJ-EVAL-0007"
    ProcessSignaled(_) => "MJ-EVAL-0015"
    InvalidUtf8(_) => "MJ-EVAL-0008"
    RecursionLimitExceeded(_) => "MJ-EVAL-0009"
    FunctionRecursionLimit(_) => "MJ-EVAL-0009"
    NodeLimitExceeded(_) => "MJ-EVAL-0010"
    OutputLimitExceeded(_) => "MJ-EVAL-0011"
    MissingContext(_) => "MJ-EVAL-0012"
    ArgumentCount(_) => "MJ-EVAL-0013"
    UnknownOverrides(_) => "MJ-EVAL-0014"
    FunctionArgumentCount(_) => "MJ-EVAL-0016"
    EmptyParameter(_) => "MJ-EVAL-0017"
  }
}

///|
pub fn EvaluationError::span(self : EvaluationError) -> @source.Span {
  match self {
    Parse(error) => error.span()
    UndefinedVariable(span~, ..) => span
    VariableCycle(span~, ..) => span
    TypeMismatch(span~, ..) => span
    Builtin(_, span~) => span
    EffectRequired(span~, ..) => span
    Host(_, span~) => span
    ProcessFailure(span~, ..) => span
    BacktickFailure(span~, ..) => span
    ProcessSignaled(span~, ..) => span
    InvalidUtf8(span~) => span
    RecursionLimitExceeded(span~, ..) => span
    FunctionRecursionLimit(span~, ..) => span
    NodeLimitExceeded(span~, ..) => span
    OutputLimitExceeded(span~, ..) => span
    MissingContext(span~, ..) => span
    ArgumentCount(span~, ..) => span
    UnknownOverrides(span~, ..) => span
    FunctionArgumentCount(span~, ..) => span
    EmptyParameter(span~, ..) => span
  }
}

///|
pub fn EvaluationError::message(self : EvaluationError) -> String {
  match self {
    Parse(error) => error.message()
    UndefinedVariable(name~, ..) => "variable `" + name + "` not defined"
    VariableCycle(name~, stack~, ..) =>
      if stack.length() == 2 && stack[0] == stack[1] {
        "variable `" + name + "` is defined in terms of itself"
      } else {
        "variable `" +
        name +
        "` depends on its own value: `" +
        stack.join(" -> ") +
        "`"
      }
    TypeMismatch(expected~, actual~, ..) =>
      "expected " + expected + ", got " + actual
    Builtin(error, ..) => error.message()
    EffectRequired(effect~, ..) =>
      "pure evaluation requires effect `" + effect + "`"
    Host(error, ..) =>
      "host capability failed during evaluation: " + Repr(error).to_string()
    ProcessFailure(code~, ..) =>
      "call to function `shell` failed: process exited with status code " +
      code.to_string()
    BacktickFailure(code~, ..) =>
      "backtick failed with exit code " + code.to_string()
    ProcessSignaled(signal~, ..) =>
      "shell command terminated by signal " + Repr(signal).to_string()
    InvalidUtf8(_) => "effect result is not valid UTF-8"
    RecursionLimitExceeded(limit~, ..) =>
      "evaluation recursion limit " + limit.to_string() + " exceeded"
    FunctionRecursionLimit(name~, limit~, ..) =>
      "maximum recursion depth of " +
      limit.to_string() +
      " exceeded while calling function " +
      name
    NodeLimitExceeded(limit~, ..) =>
      "evaluation node limit " + limit.to_string() + " exceeded"
    OutputLimitExceeded(limit~, ..) =>
      "evaluation output limit " + limit.to_string() + " exceeded"
    MissingContext(fact~, ..) =>
      "evaluation context does not provide `" + fact + "`"
    ArgumentCount(recipe~, expected~, actual~, ..) =>
      "recipe `" +
      recipe +
      "` expects " +
      expected +
      " arguments, got " +
      actual.to_string()
    UnknownOverrides(names~, ..) =>
      (if names.length() == 1 { "variable " } else { "variables " }) +
      names.map(fn(name) { "`" + name + "`" }).join(" and ") +
      " overridden on the command line but not present in justfile"
    FunctionArgumentCount(name~, expected~, actual~, ..) =>
      "function `" +
      name +
      "` expects " +
      expected.to_string() +
      " arguments, got " +
      actual.to_string()
    EmptyParameter(recipe~, parameter~, ..) =>
      "recipe `" +
      recipe +
      "` parameter `" +
      parameter +
      "` requires at least one element but received empty list"
  }
}

///|
/// Normalize host failures at the user-facing evaluator boundary. Internal
/// enum representations are implementation details and are not part of the
/// just-compatible diagnostic contract.
fn host_error_detail(error : @host.HostError) -> String {
  match error {
    InvalidInput(detail) => normalize_host_io_detail(detail)
    PermissionDenied(_, detail~) => detail
    NotFound(_) => "No such file or directory (os error 2)"
    AlreadyExists(_) => "File exists (os error 17)"
    _ => Repr(error).to_string()
  }
}

///|
fn canonicalize_host_error_detail(
  error : @host.HostError,
  path : @path.PathValue,
) -> String {
  if path.flavor() == Windows {
    match error {
      NotFound(_) => "The system cannot find the file specified. (os error 2)"
      InvalidInput(detail) if detail.contains("No such file or directory") ||
        detail.contains("The system cannot find the file specified") =>
        "The system cannot find the file specified. (os error 2)"
      _ => host_error_detail(error)
    }
  } else {
    host_error_detail(error)
  }
}

///|
fn normalize_host_io_detail(detail : String) -> String {
  if detail.contains("No such file or directory") {
    "No such file or directory (os error 2)"
  } else {
    detail
  }
}

///|
pub fn EvaluationError::to_diagnostic(
  self : EvaluationError,
) -> @diagnostic.Diagnostic raise @diagnostic.DiagnosticError {
  @diagnostic.Diagnostic::new(
    self.code(),
    Error,
    self.message(),
    self.span(),
    "",
  )
}
