///|
pub struct RecipeRequest {
  recipe : String
  arguments : Array[@value.Value]
} derive(Eq, Debug)

///|
pub fn RecipeRequest::new(
  recipe : String,
  arguments? : Array[@value.Value] = [],
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
pub struct ProjectRecipeRequest {
  module_path : @modulepath.ModulePath
  recipe : String
  arguments : Array[@value.Value]
} derive(Eq, Debug)

///|
pub fn ProjectRecipeRequest::new(
  module_path : @modulepath.ModulePath,
  recipe : String,
  arguments? : Array[@value.Value] = [],
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
pub struct ProjectModuleRuntime {
  module_path : @modulepath.ModulePath
  global : @evaluator.Environment
  context : @evaluator.EvaluationContext
  shell : @environment.ShellConfiguration
  cwd : @path.PathValue
  process_environment : Array[(String, String)]
  configuration : ScriptConfiguration
} derive(Debug)

///|
pub fn ProjectModuleRuntime::new(
  module_path : @modulepath.ModulePath,
  global : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  process_environment : ArrayView[(String, String)],
  configuration : ScriptConfiguration,
) -> ProjectModuleRuntime {
  {
    module_path,
    global,
    context,
    shell,
    cwd,
    process_environment: process_environment.to_owned(),
    configuration,
  }
}

///|
pub fn ProjectModuleRuntime::module_path(
  self : ProjectModuleRuntime,
) -> @modulepath.ModulePath {
  self.module_path
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
