///|
/// Static errors found while compiling a syntax tree.
pub(all) suberror SemanticError {
  Parse(@parser.ParserError)
  DuplicateRecipe(name~ : String, first~ : @source.Span, second~ : @source.Span)
  DuplicateVariable(
    name~ : String,
    first~ : @source.Span,
    second~ : @source.Span
  )
  UndefinedRecipe(name~ : String, span~ : @source.Span)
  UndefinedVariable(name~ : String, span~ : @source.Span)
  AliasCycle(name~ : String, span~ : @source.Span)
  DependencyCycle(name~ : String, span~ : @source.Span)
  InvalidParameters(name~ : String, span~ : @source.Span)
  SettingConflict(first~ : String, second~ : String, span~ : @source.Span)
  AttributeConflict(first~ : String, second~ : String, span~ : @source.Span)
  UnsupportedPlatform(name~ : String, span~ : @source.Span)
} derive(Eq, Debug)

///|
pub fn SemanticError::code(self : SemanticError) -> String {
  match self {
    Parse(_) => "MJ-SEM-0000"
    DuplicateRecipe(_) => "MJ-SEM-0001"
    DuplicateVariable(_) => "MJ-SEM-0002"
    UndefinedRecipe(_) => "MJ-SEM-0003"
    UndefinedVariable(_) => "MJ-SEM-0004"
    AliasCycle(_) => "MJ-SEM-0005"
    DependencyCycle(_) => "MJ-SEM-0006"
    InvalidParameters(_) => "MJ-SEM-0007"
    SettingConflict(_) => "MJ-SEM-0008"
    AttributeConflict(_) => "MJ-SEM-0009"
    UnsupportedPlatform(_) => "MJ-SEM-0010"
  }
}

///|
pub fn SemanticError::span(self : SemanticError) -> @source.Span {
  match self {
    Parse(error) => error.span()
    DuplicateRecipe(second~, ..) => second
    DuplicateVariable(second~, ..) => second
    UndefinedRecipe(span~, ..) => span
    UndefinedVariable(span~, ..) => span
    AliasCycle(span~, ..) => span
    DependencyCycle(span~, ..) => span
    InvalidParameters(span~, ..) => span
    SettingConflict(span~, ..) => span
    AttributeConflict(span~, ..) => span
    UnsupportedPlatform(span~, ..) => span
  }
}

///|
pub fn SemanticError::message(self : SemanticError) -> String {
  match self {
    Parse(error) => error.message()
    DuplicateRecipe(name~, ..) =>
      "recipe `" + name + "` is defined more than once"
    DuplicateVariable(name~, ..) =>
      "variable `" + name + "` is defined more than once"
    UndefinedRecipe(name~, ..) => "recipe `" + name + "` is not defined"
    UndefinedVariable(name~, ..) => "variable `" + name + "` is not defined"
    AliasCycle(name~, ..) => "alias cycle includes `" + name + "`"
    DependencyCycle(name~, ..) => "dependency cycle includes `" + name + "`"
    InvalidParameters(name~, ..) =>
      "invalid parameters for recipe `" + name + "`"
    SettingConflict(first~, second~, ..) =>
      "settings `" + first + "` and `" + second + "` cannot be used together"
    AttributeConflict(first~, second~, ..) =>
      "attributes `" + first + "` and `" + second + "` cannot be used together"
    UnsupportedPlatform(name~, ..) =>
      "attribute `" + name + "` is not applicable to this platform"
  }
}

///|
pub fn SemanticError::to_diagnostic(
  self : SemanticError,
) -> @diagnostic.Diagnostic raise @diagnostic.DiagnosticError {
  @diagnostic.Diagnostic::new(
    self.code(),
    Error,
    self.message(),
    self.span(),
    "semantic error",
  )
}
