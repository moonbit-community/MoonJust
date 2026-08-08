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
  InvalidUtf8(span~ : @source.Span)
  RecursionLimitExceeded(limit~ : Int, span~ : @source.Span)
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
    InvalidUtf8(_) => "MJ-EVAL-0008"
    RecursionLimitExceeded(_) => "MJ-EVAL-0009"
    NodeLimitExceeded(_) => "MJ-EVAL-0010"
    OutputLimitExceeded(_) => "MJ-EVAL-0011"
    MissingContext(_) => "MJ-EVAL-0012"
    ArgumentCount(_) => "MJ-EVAL-0013"
    UnknownOverrides(_) => "MJ-EVAL-0014"
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
    InvalidUtf8(span~) => span
    RecursionLimitExceeded(span~, ..) => span
    NodeLimitExceeded(span~, ..) => span
    OutputLimitExceeded(span~, ..) => span
    MissingContext(span~, ..) => span
    ArgumentCount(span~, ..) => span
    UnknownOverrides(span~, ..) => span
  }
}

///|
pub fn EvaluationError::message(self : EvaluationError) -> String {
  match self {
    Parse(error) => error.message()
    UndefinedVariable(name~, ..) => "variable `" + name + "` is not defined"
    VariableCycle(name~, stack~, ..) =>
      "variable cycle includes `" + name + "`: " + stack.join(" -> ")
    TypeMismatch(expected~, actual~, ..) =>
      "expected " + expected + ", got " + actual
    Builtin(error, ..) => error.message()
    EffectRequired(effect~, ..) =>
      "pure evaluation requires effect `" + effect + "`"
    Host(_, ..) => "host capability failed during evaluation"
    ProcessFailure(code~, ..) =>
      "shell command exited with code " + code.to_string()
    InvalidUtf8(_) => "effect result is not valid UTF-8"
    RecursionLimitExceeded(limit~, ..) =>
      "evaluation recursion limit " + limit.to_string() + " exceeded"
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
      (if names.length() == 1 { " was" } else { " were" }) +
      " overridden on the command line but not present in justfile"
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
    "evaluation error",
  )
}
