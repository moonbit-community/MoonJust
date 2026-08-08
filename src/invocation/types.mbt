///|
/// Values supplied for one recipe parameter. Variadic and repeatable
/// parameters preserve one element per command-line occurrence.
pub struct ArgumentValue {
  elements : Array[String]
} derive(Eq, Debug)

///|
pub fn ArgumentValue::elements(self : ArgumentValue) -> ArrayView[String] {
  self.elements[:]
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
priv struct ParameterSpec {
  name : String
  defaulted : Bool
  variadic : Bool
  variadic_minimum : Int
  mut long : String?
  mut short : Char?
  mut flag : Bool
  mut value : @syntax.Expression?
  mut multiple : Bool
  mut minimum : Int?
  mut maximum : Int?
  mut pattern : @syntax.Expression?
  mut patterns : Array[String]
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
