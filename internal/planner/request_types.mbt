///|
#derive(Eq, Debug)
pub struct RecipeRequest {
  recipe : String
  arguments : Array[@value.Value]
}

///|
pub fn RecipeRequest::new(
  recipe : String,
  arguments~ : Array[@value.Value] = [],
) -> RecipeRequest {
  { recipe, arguments: arguments.copy(), }
}

///|
pub fn RecipeRequest::recipe(self : RecipeRequest) -> String {
  self.recipe
}

///|
pub fn RecipeRequest::arguments(
  self : RecipeRequest,
) -> ArrayView[@value.Value] {
  self.arguments[:]
}

///|
/// One requested recipe in an independently compiled project module.
#derive(Eq, Debug)
pub struct ProjectRecipeRequest {
  module_path : @modulepath.ModulePath
  recipe : String
  arguments : Array[@value.Value]
}

///|
pub fn ProjectRecipeRequest::new(
  module_path : @modulepath.ModulePath,
  recipe : String,
  arguments~ : Array[@value.Value] = [],
) -> ProjectRecipeRequest {
  { module_path, recipe, arguments: arguments.copy(), }
}

///|
pub fn ProjectRecipeRequest::module_path(
  self : ProjectRecipeRequest,
) -> @modulepath.ModulePath {
  self.module_path
}

///|
pub fn ProjectRecipeRequest::recipe(self : ProjectRecipeRequest) -> String {
  self.recipe
}

///|
pub fn ProjectRecipeRequest::arguments(
  self : ProjectRecipeRequest,
) -> ArrayView[@value.Value] {
  self.arguments[:]
}

///|
/// Runtime values owned by one project module during execution planning.
#derive(Debug)
pub struct ProjectModuleRuntime {
  global : @evaluator.Environment
  context : @evaluator.EvaluationContext
  shell : @environment.ShellConfiguration
  cwd : @path.PathValue
  process_environment : Array[(String, String)]
  dotenv : Array[(String, String)]
  configuration : ScriptConfiguration
}

///|
pub fn ProjectModuleRuntime::new(
  global : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  process_environment : ArrayView[(String, String)],
  configuration : ScriptConfiguration,
  dotenv~ : Array[(String, String)] = [],
) -> ProjectModuleRuntime {
  {
    global,
    context,
    shell,
    cwd,
    process_environment: process_environment.to_owned(),
    dotenv: dotenv.copy(),
    configuration,
  }
}

///|
pub fn ProjectModuleRuntime::global(
  self : ProjectModuleRuntime,
) -> @evaluator.Environment {
  self.global
}

///|
pub fn ProjectModuleRuntime::context(
  self : ProjectModuleRuntime,
) -> @evaluator.EvaluationContext {
  self.context
}

///|
pub fn ProjectModuleRuntime::shell(
  self : ProjectModuleRuntime,
) -> @environment.ShellConfiguration {
  self.shell
}

///|
pub fn ProjectModuleRuntime::cwd(
  self : ProjectModuleRuntime,
) -> @path.PathValue {
  self.cwd
}

///|
pub fn ProjectModuleRuntime::process_environment(
  self : ProjectModuleRuntime,
) -> ArrayView[(String, String)] {
  self.process_environment[:]
}

///|
pub fn ProjectModuleRuntime::configuration(
  self : ProjectModuleRuntime,
) -> ScriptConfiguration {
  self.configuration
}
