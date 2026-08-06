///|
/// Explicit variable and parameter scope for deterministic evaluation.
pub struct Environment {
  values : Map[String, @value.Value]
  ordered : Array[String]
  exported : Set[String]
} derive(Debug)

///|
pub fn Environment::new() -> Environment {
  { values: Map([]), ordered: [], exported: Set([]) }
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
