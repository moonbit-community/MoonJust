///|
/// User-defined functions visible to one expression evaluation. Standalone
/// expression APIs default to an empty table; compilation evaluation installs
/// the table owned by that compilation into its resulting environment.
pub struct FunctionEnvironment {
  definitions : Map[String, @syntax.FunctionDefinition]
} derive(Debug)

///|
pub fn FunctionEnvironment::new() -> FunctionEnvironment {
  { definitions: Map([]) }
}

///|
pub fn FunctionEnvironment::from_compilation(
  compilation : @semantic.Compilation,
) -> FunctionEnvironment {
  let definitions : Map[String, @syntax.FunctionDefinition] = Map([])
  for name in compilation.function_names() {
    definitions[name] = compilation.function(name).unwrap()
  }
  { definitions, }
}

///|
pub fn FunctionEnvironment::get(
  self : FunctionEnvironment,
  name : String,
) -> @syntax.FunctionDefinition? {
  self.definitions.get(name)
}

///|
pub fn FunctionEnvironment::names(self : FunctionEnvironment) -> Array[String] {
  self.definitions.keys().collect()
}
