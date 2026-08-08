///|
/// Failures raised while compiling recipe argument metadata or grouping argv.
pub(all) suberror InvocationError {
  NoRecipes
  DefaultRecipeRequiresArguments(recipe~ : String, minimum~ : Int)
  UnknownRecipe(recipe~ : String)
  Evaluation(@evaluator.EvaluationError)
  InvalidArgumentAttribute(recipe~ : String, detail~ : String)
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
    DefaultRecipeRequiresArguments(_) => "MJ-INV-0002"
    UnknownRecipe(_) => "MJ-INV-0003"
    Evaluation(_) => "MJ-INV-0016"
    InvalidArgumentAttribute(_) => "MJ-INV-0004"
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
  count.to_string() + " " + singular + (if count == 1 { "" } else { "s" })
}

///|
pub fn InvocationError::message(self : InvocationError) -> String {
  match self {
    NoRecipes => "justfile contains no recipes"
    DefaultRecipeRequiresArguments(recipe~, minimum~) =>
      "recipe `" +
      recipe +
      "` cannot be used as default recipe since it requires at least " +
      counted(minimum, "argument")
    UnknownRecipe(recipe~) =>
      "justfile does not contain recipe `" + recipe + "`"
    Evaluation(error) => error.message()
    InvalidArgumentAttribute(recipe~, detail~) =>
      "recipe `" + recipe + "` has invalid argument attribute: " + detail
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
