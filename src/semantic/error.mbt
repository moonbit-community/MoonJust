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
  DuplicateFunction(
    name~ : String,
    first~ : @source.Span,
    second~ : @source.Span
  )
  SymbolRedefinition(
    name~ : String,
    first_kind~ : String,
    second_kind~ : String,
    first~ : @source.Span,
    second~ : @source.Span
  )
  DuplicateFunctionParameter(
    function_name~ : String,
    parameter~ : String,
    span~ : @source.Span
  )
  UndefinedFunction(name~ : String, span~ : @source.Span)
  FunctionArgumentCount(
    name~ : String,
    expected~ : String,
    actual~ : Int,
    span~ : @source.Span
  )
  UserFunctionsUnstable(span~ : @source.Span)
  ListsUnstable(span~ : @source.Span)
  GuardAndInfallibleSigil(span~ : @source.Span)
  InvalidIndentation(message~ : String, span~ : @source.Span)
  UndefinedRecipe(name~ : String, span~ : @source.Span)
  UndefinedVariable(name~ : String, span~ : @source.Span)
  NonConstVariable(name~ : String, span~ : @source.Span)
  ConstContext(kind~ : String, span~ : @source.Span)
  AliasCycle(name~ : String, span~ : @source.Span)
  DependencyCycle(name~ : String, span~ : @source.Span)
  RecipeDependencyCycle(
    recipe~ : String,
    chain~ : Array[String],
    span~ : @source.Span
  )
  InvalidParameters(name~ : String, span~ : @source.Span)
  InvalidDependencyArguments(
    name~ : String,
    expected~ : String,
    actual~ : Int,
    span~ : @source.Span
  )
  SettingConflict(first~ : String, second~ : String, span~ : @source.Span)
  InvalidSettingValue(name~ : String, span~ : @source.Span)
  EmptySetting(name~ : String, span~ : @source.Span)
  MinimumVersionUnsatisfied(
    required~ : String,
    current~ : String,
    span~ : @source.Span
  )
  InvalidMinimumVersion(value~ : String, span~ : @source.Span)
  AttributeConflict(first~ : String, second~ : String, span~ : @source.Span)
  NoCdWorkingDirectoryAttributes(recipe~ : String, span~ : @source.Span)
  ScriptAndShellAttributes(recipe~ : String, span~ : @source.Span)
  ExitMessageAttributes(recipe~ : String, span~ : @source.Span)
  InvalidContinueSignal(signal~ : String, span~ : @source.Span)
  ScriptAttributeOnShellRecipe(
    recipe~ : String,
    attribute~ : String,
    span~ : @source.Span
  )
  DuplicateDefaultAttribute(recipe~ : String, span~ : @source.Span)
  DuplicateUnexport(variable~ : String, span~ : @source.Span)
  ExportUnexported(variable~ : String, span~ : @source.Span)
  InvalidMappedDependency(message~ : String, span~ : @source.Span)
  InvalidItemAttribute(
    item_kind~ : String,
    item_name~ : String,
    attribute~ : String,
    span~ : @source.Span
  )
  ListsFeature(message~ : String, span~ : @source.Span)
  UnsupportedPlatform(name~ : String, span~ : @source.Span)
} derive(Eq, Debug)

///|
pub fn SemanticError::code(self : SemanticError) -> String {
  match self {
    Parse(_) => "MJ-SEM-0000"
    DuplicateRecipe(_) => "MJ-SEM-0001"
    DuplicateVariable(_) => "MJ-SEM-0002"
    DuplicateFunction(_) => "MJ-SEM-0014"
    SymbolRedefinition(_) => "MJ-SEM-0030"
    DuplicateFunctionParameter(_) => "MJ-SEM-0015"
    UndefinedFunction(_) => "MJ-SEM-0016"
    FunctionArgumentCount(_) => "MJ-SEM-0017"
    UserFunctionsUnstable(_) => "MJ-SEM-0018"
    ListsUnstable(_) => "MJ-SEM-0019"
    GuardAndInfallibleSigil(_) => "MJ-SEM-0019"
    InvalidIndentation(_) => "MJ-SEM-0020"
    UndefinedRecipe(_) => "MJ-SEM-0003"
    UndefinedVariable(_) => "MJ-SEM-0004"
    NonConstVariable(_) => "MJ-SEM-0021"
    ConstContext(_) => "MJ-SEM-0034"
    AliasCycle(_) => "MJ-SEM-0005"
    DependencyCycle(_) => "MJ-SEM-0006"
    RecipeDependencyCycle(_) => "MJ-SEM-0006"
    InvalidParameters(_) => "MJ-SEM-0007"
    InvalidDependencyArguments(_) => "MJ-SEM-0008"
    SettingConflict(_) => "MJ-SEM-0009"
    InvalidSettingValue(_) => "MJ-SEM-0010"
    EmptySetting(_) => "MJ-SEM-0035"
    MinimumVersionUnsatisfied(_) => "MJ-SEM-0011"
    InvalidMinimumVersion(_) => "MJ-SEM-0031"
    AttributeConflict(_) => "MJ-SEM-0012"
    NoCdWorkingDirectoryAttributes(_) => "MJ-SEM-0036"
    ScriptAndShellAttributes(_) => "MJ-SEM-0032"
    ExitMessageAttributes(_) => "MJ-SEM-0033"
    InvalidContinueSignal(_) => "MJ-SEM-0022"
    ScriptAttributeOnShellRecipe(_) => "MJ-SEM-0023"
    DuplicateDefaultAttribute(_) => "MJ-SEM-0024"
    DuplicateUnexport(_) => "MJ-SEM-0025"
    ExportUnexported(_) => "MJ-SEM-0026"
    InvalidMappedDependency(_) => "MJ-SEM-0027"
    InvalidItemAttribute(_) => "MJ-SEM-0028"
    ListsFeature(_) => "MJ-SEM-0029"
    UnsupportedPlatform(_) => "MJ-SEM-0013"
  }
}

///|
pub fn SemanticError::span(self : SemanticError) -> @source.Span {
  match self {
    Parse(error) => error.span()
    DuplicateRecipe(second~, ..) => second
    DuplicateVariable(second~, ..) => second
    DuplicateFunction(second~, ..) => second
    SymbolRedefinition(second~, ..) => second
    DuplicateFunctionParameter(span~, ..) => span
    UndefinedFunction(span~, ..) => span
    FunctionArgumentCount(span~, ..) => span
    UserFunctionsUnstable(span~) => span
    ListsUnstable(span~) => span
    GuardAndInfallibleSigil(span~) => span
    InvalidIndentation(span~, ..) => span
    UndefinedRecipe(span~, ..) => span
    UndefinedVariable(span~, ..) => span
    NonConstVariable(span~, ..) => span
    ConstContext(span~, ..) => span
    AliasCycle(span~, ..) => span
    DependencyCycle(span~, ..) => span
    RecipeDependencyCycle(span~, ..) => span
    InvalidParameters(span~, ..) => span
    InvalidDependencyArguments(span~, ..) => span
    SettingConflict(span~, ..) => span
    InvalidSettingValue(span~, ..) => span
    EmptySetting(span~, ..) => span
    MinimumVersionUnsatisfied(span~, ..) => span
    InvalidMinimumVersion(span~, ..) => span
    AttributeConflict(span~, ..) => span
    NoCdWorkingDirectoryAttributes(span~, ..) => span
    ScriptAndShellAttributes(span~, ..) => span
    ExitMessageAttributes(span~, ..) => span
    InvalidContinueSignal(span~, ..) => span
    ScriptAttributeOnShellRecipe(span~, ..) => span
    DuplicateDefaultAttribute(span~, ..) => span
    DuplicateUnexport(span~, ..) => span
    ExportUnexported(span~, ..) => span
    InvalidMappedDependency(span~, ..) => span
    InvalidItemAttribute(span~, ..) => span
    ListsFeature(span~, ..) => span
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
    DuplicateFunction(name~, ..) =>
      "function `" + name + "` is defined more than once"
    SymbolRedefinition(name~, first_kind~, second_kind~, ..) =>
      first_kind + " `" + name + "` is redefined as a " + second_kind
    DuplicateFunctionParameter(function_name~, parameter~, ..) =>
      "function `" +
      function_name +
      "` has duplicate parameter `" +
      parameter +
      "`"
    UndefinedFunction(name~, ..) => "call to undefined function `" + name + "`"
    FunctionArgumentCount(name~, expected~, actual~, ..) =>
      "function `" +
      name +
      "` called with " +
      actual.to_string() +
      " arguments but takes " +
      expected
    UserFunctionsUnstable(_) =>
      "user-defined functions are currently unstable; pass `--unstable` or add `set unstable`"
    ListsUnstable(_) =>
      "the `lists` setting is currently unstable; pass `--unstable` or add `set unstable`"
    GuardAndInfallibleSigil(_) =>
      "the guard `?` and infallible `-` sigils may not be used together"
    InvalidIndentation(message~, ..) => message
    UndefinedRecipe(name~, ..) => "recipe `" + name + "` is not defined"
    UndefinedVariable(name~, ..) => "variable `" + name + "` is not defined"
    NonConstVariable(name~, ..) =>
      "cannot access non-const variable `" + name + "` in const context"
    ConstContext(kind~, ..) => "cannot call " + kind + " in const context"
    AliasCycle(name~, ..) => "alias cycle includes `" + name + "`"
    DependencyCycle(name~, ..) => "dependency cycle includes `" + name + "`"
    RecipeDependencyCycle(recipe~, chain~, ..) =>
      "recipe `" +
      recipe +
      "` has circular dependency `" +
      chain.join(" -> ") +
      "`"
    InvalidParameters(name~, ..) =>
      "invalid parameters for recipe `" + name + "`"
    InvalidDependencyArguments(name~, expected~, actual~, ..) =>
      "dependency `" +
      name +
      "` expects " +
      expected +
      " arguments, got " +
      actual.to_string()
    SettingConflict(first~, second~, ..) =>
      "settings `" + first + "` and `" + second + "` cannot be used together"
    InvalidSettingValue(name~, ..) =>
      "setting `" + name + "` has a value of the wrong type"
    EmptySetting(name~, ..) =>
      "`" +
      name +
      "` setting requires at least one element but evaluated to empty list"
    MinimumVersionUnsatisfied(required~, current~, ..) =>
      "minimum version `" +
      required +
      "` is newer than MoonJust `" +
      current +
      "`"
    InvalidMinimumVersion(value~, ..) =>
      "`minimum-version` setting has invalid version `" +
      value +
      "`: expected `MAJOR.MINOR.PATCH`"
    AttributeConflict(first~, second~, ..) =>
      "attributes `" + first + "` and `" + second + "` cannot be used together"
    NoCdWorkingDirectoryAttributes(recipe~, ..) =>
      "recipe `" +
      recipe +
      "` has both `[no-cd]` and `[working-directory]` attributes"
    ScriptAndShellAttributes(recipe~, ..) =>
      "recipe `" + recipe + "` has both `[script]` and `[shell]` attributes"
    ExitMessageAttributes(recipe~, ..) =>
      "recipe `" +
      recipe +
      "` has both `[exit-message]` and `[no-exit-message]` attributes"
    InvalidContinueSignal(signal~, ..) =>
      "invalid signal `" +
      signal +
      "`: expected `SIGHUP`, `SIGINT`, or `SIGQUIT`"
    ScriptAttributeOnShellRecipe(recipe~, attribute~, ..) =>
      "shell recipe `" +
      recipe +
      "` has script recipe attribute `" +
      attribute +
      "`"
    DuplicateDefaultAttribute(recipe~, ..) =>
      "recipe `" +
      recipe +
      "` has duplicate `[default]` attribute, which may only appear once per module"
    DuplicateUnexport(variable~, ..) =>
      "variable `" + variable + "` is unexported multiple times"
    ExportUnexported(variable~, ..) =>
      "variable " + variable + " is both exported and unexported"
    InvalidMappedDependency(message~, ..) => message
    InvalidItemAttribute(item_kind~, item_name~, attribute~, ..) =>
      item_kind +
      " `" +
      item_name +
      "` has invalid attribute `" +
      attribute +
      "`"
    ListsFeature(message~, ..) => message
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
