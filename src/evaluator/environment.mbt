///|
/// Explicit variable and parameter scope for deterministic evaluation.
pub struct Environment {
  values : Map[String, @value.Value]
} derive(Debug)

///|
pub fn Environment::new() -> Environment {
  { values: Map([]) }
}

///|
pub fn Environment::set(
  self : Environment,
  name : String,
  value : @value.Value,
) -> Unit {
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
