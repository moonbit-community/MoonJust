///|
/// Failures raised while compiling recipe argument metadata or grouping argv.
pub(all) suberror InvocationError {
  NoRecipes
  NoDefaultRecipe
  DefaultRecipeRequiresArguments(recipe~ : String, minimum~ : Int)
  UnknownRecipe(recipe~ : String)
  UnknownRecipeSuggested(
    recipe~ : String,
    suggestion~ : String,
    alias_target~ : String?
  )
  UnknownSubmodule(name~ : String, suggestion~ : String?)
  ExpectedSubmoduleFoundRecipe(path~ : String)
  DisabledRecipe(name~ : String, modules~ : Array[String], is_alias~ : Bool)
  OptionalModuleAbsent(module_path~ : String)
  Evaluation(@evaluator.EvaluationError)
  InvalidArgumentAttribute(
    recipe~ : String,
    detail~ : String,
    span~ : @source.Span?
  )
  InvalidArgumentPattern(
    recipe~ : String,
    detail~ : String,
    cause~ : String,
    span~ : @source.Span?
  )
  DuplicateArgumentAttribute(
    name~ : String,
    first~ : @source.Span,
    second~ : @source.Span
  )
  DuplicateDefinitionOption(
    recipe~ : String,
    option~ : String,
    span~ : @source.Span
  )
  InvalidOption(argument~ : String)
  UnknownOption(recipe~ : String, option~ : String)
  FlagWithValue(recipe~ : String, option~ : String)
  NonFinalOptionWithValue(recipe~ : String, option~ : String)
  OptionMissingValue(recipe~ : String, option~ : String)
  DuplicateOption(recipe~ : String, option~ : String)
  MissingOption(recipe~ : String, option~ : String)
  PositionalArgumentCountMismatch(
    recipe~ : String,
    found~ : Int,
    minimum~ : Int,
    maximum~ : Int?,
    usage~ : String
  )
  ArgumentTooFewValues(
    recipe~ : String,
    parameter~ : String,
    found~ : Int,
    minimum~ : Int
  )
  ArgumentTooManyValues(
    recipe~ : String,
    parameter~ : String,
    found~ : Int,
    maximum~ : Int
  )
  ArgumentPatternMismatch(
    recipe~ : String,
    parameter~ : String,
    argument~ : String,
    patterns~ : Array[String]
  )
} derive(Eq, Debug)

///|
pub fn InvocationError::code(self : InvocationError) -> String {
  match self {
    NoRecipes => "MJ-INV-0001"
    NoDefaultRecipe => "MJ-INV-0019"
    DefaultRecipeRequiresArguments(_) => "MJ-INV-0002"
    UnknownRecipe(_)
    | UnknownRecipeSuggested(_)
    | UnknownSubmodule(_)
    | ExpectedSubmoduleFoundRecipe(_) => "MJ-INV-0003"
    DisabledRecipe(_) => "MJ-INV-0017"
    OptionalModuleAbsent(_) => "MJ-INV-0018"
    Evaluation(_) => "MJ-INV-0016"
    InvalidArgumentAttribute(_) | InvalidArgumentPattern(_) => "MJ-INV-0004"
    DuplicateArgumentAttribute(_) => "MJ-INV-0020"
    DuplicateDefinitionOption(_) => "MJ-INV-0004"
    InvalidOption(_) => "MJ-INV-0005"
    UnknownOption(_) => "MJ-INV-0006"
    FlagWithValue(_) => "MJ-INV-0007"
    NonFinalOptionWithValue(_) => "MJ-INV-0008"
    OptionMissingValue(_) => "MJ-INV-0009"
    DuplicateOption(_) => "MJ-INV-0010"
    MissingOption(_) => "MJ-INV-0011"
    PositionalArgumentCountMismatch(_) => "MJ-INV-0012"
    ArgumentTooFewValues(_) => "MJ-INV-0013"
    ArgumentTooManyValues(_) => "MJ-INV-0014"
    ArgumentPatternMismatch(_) => "MJ-INV-0015"
  }
}

///|
fn counted(count : Int, singular : String) -> String {
  @diagnostic.Count::numbered(singular, count).to_string()
}

///|
pub fn InvocationError::message(self : InvocationError) -> String {
  match self {
    NoRecipes => "justfile contains no recipes"
    NoDefaultRecipe => "justfile contains no default recipe"
    DefaultRecipeRequiresArguments(recipe~, minimum~) =>
      "recipe `" +
      recipe +
      "` cannot be used as default recipe since it requires at least " +
      counted(minimum, "argument")
    UnknownRecipe(recipe~) =>
      "justfile does not contain recipe `" + recipe + "`"
    UnknownRecipeSuggested(recipe~, suggestion~, alias_target~) => {
      let suffix = match alias_target {
        Some(target) => ", an alias for `" + target + "`?"
        None => "?"
      }
      "justfile does not contain recipe `" +
      recipe +
      "`\nDid you mean `" +
      suggestion +
      "`" +
      suffix
    }
    UnknownSubmodule(name~, suggestion~) => {
      let suffix = suggestion
        .map(fn(value) { "\nDid you mean `" + value + "`?" })
        .unwrap_or("")
      "justfile does not contain submodule `" + name + "`" + suffix
    }
    ExpectedSubmoduleFoundRecipe(path~) =>
      "expected submodule at `" + path + "` but found recipe"
    DisabledRecipe(name~, modules~, is_alias~) => {
      let subject = if is_alias { "alias" } else { "recipe" }
      let module_text = if modules.length() == 1 {
        "module `" + modules[0] + "`"
      } else {
        "modules " +
        modules.map(fn(module_path) { "`" + module_path + "`" }).join(" and ")
      }
      subject + " `" + name + "` depends on absent " + module_text
    }
    OptionalModuleAbsent(module_path~) =>
      "optional module `" + module_path + "` is absent"
    Evaluation(error) => error.message()
    InvalidArgumentAttribute(detail~, ..) => detail
    InvalidArgumentPattern(detail~, ..) => detail
    DuplicateArgumentAttribute(name~, ..) =>
      "attribute for argument `" + name + "` is duplicated"
    DuplicateDefinitionOption(recipe~, option~, ..) =>
      "recipe `" + recipe + "` defines option `" + option + "` multiple times"
    InvalidOption(argument~) =>
      "argument `" + argument + "` is not a valid option"
    UnknownOption(recipe~, option~) =>
      "recipe `" + recipe + "` does not have option `" + option + "`"
    FlagWithValue(recipe~, option~) =>
      "recipe `" + recipe + "` flag `" + option + "` does not take value"
    NonFinalOptionWithValue(recipe~, option~) =>
      "recipe `" +
      recipe +
      "` option `" +
      option +
      "` takes a value and so must be last when combined with other options"
    OptionMissingValue(recipe~, option~) =>
      "recipe `" + recipe + "` option `" + option + "` missing value"
    DuplicateOption(recipe~, option~) =>
      "recipe `" +
      recipe +
      "` option `" +
      option +
      "` cannot be passed more than once"
    MissingOption(recipe~, option~) =>
      "recipe `" + recipe + "` requires option `" + option + "`"
    PositionalArgumentCountMismatch(recipe~, found~, minimum~, maximum~, usage~) => {
      let actual = counted(found, "positional argument")
      let expectation = match maximum {
        Some(maximum) if minimum == maximum =>
          (if found > maximum { "only " } else { "" }) +
          "takes " +
          minimum.to_string()
        Some(maximum) if found > maximum =>
          "takes at most " + maximum.to_string()
        _ => "takes at least " + minimum.to_string()
      }
      "recipe `" +
      recipe +
      "` got " +
      actual +
      " but " +
      expectation +
      "\nusage:\n    " +
      usage
    }
    ArgumentTooFewValues(recipe~, parameter~, found~, minimum~) =>
      "recipe `" +
      recipe +
      "` parameter `" +
      parameter +
      "` got " +
      counted(found, "value") +
      " but takes at least " +
      minimum.to_string()
    ArgumentTooManyValues(recipe~, parameter~, found~, maximum~) =>
      "recipe `" +
      recipe +
      "` parameter `" +
      parameter +
      "` got " +
      counted(found, "value") +
      " but takes at most " +
      maximum.to_string()
    ArgumentPatternMismatch(recipe~, parameter~, argument~, patterns~) =>
      "argument `" +
      argument +
      "` passed to recipe `" +
      recipe +
      "` parameter `" +
      parameter +
      "` does not match pattern " +
      patterns.map(fn(pattern) { "`" + pattern + "`" }).join(" or ")
  }
}

///|
pub fn InvocationError::span(self : InvocationError) -> @source.Span? {
  match self {
    InvalidArgumentAttribute(span~, ..) | InvalidArgumentPattern(span~, ..) =>
      span
    DuplicateArgumentAttribute(second~, ..) => Some(second)
    DuplicateDefinitionOption(span~, ..) => Some(span)
    Evaluation(error) => Some(error.span())
    _ => None
  }
}

///|
pub fn InvocationError::to_diagnostic(
  self : InvocationError,
) -> @diagnostic.Diagnostic? raise @diagnostic.DiagnosticError {
  match self.span() {
    Some(span) => {
      let diagnostic = @diagnostic.Diagnostic::new(
        self.code(),
        Error,
        self.message(),
        span,
        "",
      )
      match self {
        DuplicateArgumentAttribute(first~, ..) => diagnostic.add_related(first)
        InvalidArgumentPattern(cause~, ..) =>
          diagnostic.add_trailer("caused by: " + cause)
        _ => ()
      }
      Some(diagnostic)
    }
    None => None
  }
}
