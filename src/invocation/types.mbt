///|
/// Values supplied for one recipe parameter. Variadic and repeatable
/// parameters preserve one element per command-line occurrence.
pub struct ArgumentValue {
  elements : Array[String]
  list : Bool
} derive(Eq, Debug)

///|
pub fn ArgumentValue::elements(self : ArgumentValue) -> ArrayView[String] {
  self.elements[:]
}

///|
/// Whether this argument is represented by just's list-valued option model.
pub fn ArgumentValue::list(self : ArgumentValue) -> Bool {
  self.list
}

///|
/// One parsed recipe invocation with values in recipe parameter order.
pub struct Invocation {
  recipe : String
  arguments : Array[ArgumentValue]
} derive(Eq, Debug)

///|
pub fn Invocation::recipe(self : Invocation) -> String {
  self.recipe
}

///|
pub fn Invocation::arguments(self : Invocation) -> ArrayView[ArgumentValue] {
  self.arguments[:]
}

///|
/// One invocation resolved against a concrete project module. The contained
/// recipe name is local to that module; `module_path` carries its full scope.
pub struct ProjectInvocation {
  module_path : @modulepath.ModulePath
  invocation : Invocation
} derive(Eq, Debug)

///|
pub fn ProjectInvocation::module_path(
  self : ProjectInvocation,
) -> @modulepath.ModulePath {
  self.module_path
}

///|
pub fn ProjectInvocation::invocation(self : ProjectInvocation) -> Invocation {
  self.invocation
}

///|
priv struct ParameterSpec {
  name : String
  span : @source.Span
  defaulted : Bool
  variadic : Bool
  variadic_minimum : Int
  mut long : String?
  mut short : Char?
  mut long_defaulted : Bool
  mut flag : Bool
  mut value : @syntax.Expression?
  mut multiple : Bool
  mut minimum : Int?
  mut maximum : Int?
  mut pattern : @syntax.Expression?
  mut patterns : Array[String]
  mut long_span : @source.Span?
  mut short_span : @source.Span?
  mut flag_span : @source.Span?
  mut value_span : @source.Span?
  mut multiple_span : @source.Span?
  mut minimum_span : @source.Span?
  mut maximum_span : @source.Span?
  mut pattern_span : @source.Span?
}

///|
fn ParameterSpec::is_option(self : ParameterSpec) -> Bool {
  self.long is Some(_) || self.short is Some(_)
}

///|
fn ParameterSpec::is_required(self : ParameterSpec) -> Bool {
  !self.defaulted &&
  !self.flag &&
  (self.variadic_minimum > 0 || !self.variadic || self.minimum.unwrap_or(0) > 0)
}

///|
priv struct RecipeSpec {
  name : String
  parameters : Array[ParameterSpec]
}
