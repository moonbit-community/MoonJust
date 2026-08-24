///|
/// Explicit variable and parameter scope for deterministic evaluation.
pub struct Environment {
  values : Map[String, @value.Value]
  ordered : Array[String]
  exported : Set[String]
  mut functions : FunctionEnvironment
} derive(Debug)

///|
pub fn Environment::new() -> Environment {
  {
    values: Map([]),
    ordered: [],
    exported: Set([]),
    functions: FunctionEnvironment::new(),
  }
}

///|
/// Create a child scope with a deterministic snapshot of the parent values.
pub fn Environment::child(parent : Environment) -> Environment {
  let result = Environment::new()
  for name in parent.ordered {
    match parent.values.get(name) {
      Some(value) => result.set(name, value)
      None => ()
    }
  }
  for name in parent.ordered {
    if parent.exported.contains(name) {
      result.mark_exported(name)
    }
  }
  result.functions = parent.functions
  result
}

///|
/// Create a module scope containing only explicitly exported parent values.
pub fn Environment::module_scope(parent : Environment) -> Environment {
  let result = Environment::new()
  for name in parent.ordered {
    if parent.exported.contains(name) {
      match parent.values.get(name) {
        Some(value) => {
          result.set(name, value)
          result.mark_exported(name)
        }
        None => ()
      }
    }
  }
  result
}

///|
pub fn Environment::set(
  self : Environment,
  name : String,
  value : @value.Value,
) -> Unit {
  if !self.values.contains(name) {
    self.ordered.push(name)
  }
  self.values[name] = value
}

///|
pub fn Environment::get(self : Environment, name : String) -> @value.Value? {
  self.values.get(name)
}

///|
pub fn Environment::contains(self : Environment, name : String) -> Bool {
  self.values.contains(name)
}

///|
pub fn Environment::remove(self : Environment, name : String) -> Unit {
  self.values.remove(name)
  self.exported.remove(name)
  for index, value in self.ordered {
    if value == name {
      ignore(self.ordered.remove(index))
      break
    }
  }
}

///|
pub fn Environment::names(self : Environment) -> ArrayView[String] {
  self.ordered[:]
}

///|
pub fn Environment::mark_exported(self : Environment, name : String) -> Unit {
  self.exported.add(name)
}

///|
pub fn Environment::is_exported(self : Environment, name : String) -> Bool {
  self.exported.contains(name)
}

///|
pub fn Environment::set_functions(
  self : Environment,
  functions : FunctionEnvironment,
) -> Unit {
  self.functions = functions
}

///|
pub fn Environment::functions(self : Environment) -> FunctionEnvironment {
  self.functions
}
