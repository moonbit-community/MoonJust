///|
pub(all) suberror ModulePathError {
  InvalidModulePath(String)
} derive(Eq, Debug)

///|
/// A normalized module path. Root is represented by an empty component list;
/// non-root paths use the canonical `::` separator.
pub struct ModulePath {
  components : Array[String]
} derive(Eq, Hash, Debug)

///|
fn valid_start(code : UInt16) -> Bool {
  let value = code.to_int()
  (value >= 97 && value <= 122) || (value >= 65 && value <= 90) || value == 95
}

///|
fn valid_continue(code : UInt16) -> Bool {
  let value = code.to_int()
  valid_start(code) || (value >= 48 && value <= 57) || value == 45
}

///|
fn validate_component(component : String) -> Bool {
  if component.is_empty() || !valid_start(component.unsafe_get(0)) {
    return false
  }
  for index in 1..<component.length() {
    if !valid_continue(component.unsafe_get(index)) {
      return false
    }
  }
  true
}

///|
pub fn ModulePath::root() -> ModulePath {
  { components: [], }
}

///|
pub fn ModulePath::new(
  components : Array[String],
) -> ModulePath raise ModulePathError {
  for component in components {
    if !validate_component(component) {
      raise InvalidModulePath(components.join("::"))
    }
  }
  { components: components.copy(), }
}

///|
pub fn ModulePath::parse(value : String) -> ModulePath raise ModulePathError {
  let normalized = value.strip_suffix("::").unwrap_or(value[:]).to_owned()
  if normalized.is_empty() {
    return ModulePath::root()
  }
  if normalized.has_prefix(":") ||
    normalized.has_suffix(":") ||
    normalized.contains(":::") {
    raise InvalidModulePath(value)
  }
  let components : Array[String] = []
  for part in normalized.split("::") {
    components.push(part.to_owned())
  }
  ModulePath::new(components)
}

///|
pub fn ModulePath::components(self : ModulePath) -> ArrayView[String] {
  self.components[:]
}

///|
pub fn ModulePath::is_root(self : ModulePath) -> Bool {
  self.components.is_empty()
}

///|
pub fn ModulePath::child(
  self : ModulePath,
  name : String,
) -> ModulePath raise ModulePathError {
  let components = self.components.copy()
  components.push(name)
  ModulePath::new(components)
}

///|
pub fn ModulePath::parent(self : ModulePath) -> ModulePath? {
  if self.components.is_empty() {
    return None
  }
  Some({
    components: self.components[:self.components.length() - 1].to_owned(),
  })
}

///|
pub fn ModulePath::as_string(self : ModulePath) -> String {
  self.components.join("::")
}

///|
pub fn ModulePath::starts_with(self : ModulePath, prefix : ModulePath) -> Bool {
  if prefix.components.length() > self.components.length() {
    return false
  }
  for index, component in prefix.components {
    if self.components[index] != component {
      return false
    }
  }
  true
}
