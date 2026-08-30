///|
/// A deterministic environment snapshot. Values are deliberately excluded
/// from `Debug` output so diagnostics cannot accidentally disclose secrets.
pub(all) enum EnvNameMode {
  Sensitive
  AsciiInsensitive
} derive(Eq, Debug)

///|
pub struct EnvTable {
  values : Map[String, String]
  ordered : Array[String]
  name_mode : EnvNameMode
}

///|
pub fn EnvTable::new(name_mode? : EnvNameMode = Sensitive) -> EnvTable {
  { values: Map([]), ordered: [], name_mode, }
}

///|
pub fn EnvTable::from_entries(
  entries : ArrayView[(String, String)],
  name_mode? : EnvNameMode = Sensitive,
) -> EnvTable {
  let table = EnvTable::new(name_mode~)
  for entry in entries {
    table.set(entry.0, entry.1)
  }
  table
}

///|
fn lower_ascii(value : String) -> String {
  let builder = StringBuilder()
  for character in value {
    if character.is_ascii_uppercase() {
      builder.write_char((character.to_int() + 32).to_char().unwrap())
    } else {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
fn EnvTable::canonical_key(self : EnvTable, key : String) -> String {
  match self.name_mode {
    Sensitive => key
    AsciiInsensitive => lower_ascii(key)
  }
}

///|
pub fn EnvTable::name_mode(self : EnvTable) -> EnvNameMode {
  self.name_mode
}

///|
pub fn EnvTable::get(self : EnvTable, key : String) -> String? {
  self.values.get(self.canonical_key(key))
}

///|
pub fn EnvTable::contains(self : EnvTable, key : String) -> Bool {
  self.values.contains(self.canonical_key(key))
}

///|
pub fn EnvTable::set(self : EnvTable, key : String, value : String) -> Unit {
  let canonical = self.canonical_key(key)
  if !self.values.contains(canonical) {
    self.ordered.push(key)
  }
  self.values[canonical] = value
}

///|
pub fn EnvTable::remove(self : EnvTable, key : String) -> Unit {
  let canonical = self.canonical_key(key)
  if !self.values.contains(canonical) {
    return
  }
  self.values.remove(canonical)
  for index, existing in self.ordered {
    if self.canonical_key(existing) == canonical {
      ignore(self.ordered.remove(index))
      return
    }
  }
}

///|
pub fn EnvTable::merge(
  self : EnvTable,
  incoming : EnvTable,
  override_existing? : Bool = true,
) -> Unit {
  for entry in incoming.entries() {
    if override_existing || !self.contains(entry.0) {
      self.set(entry.0, entry.1)
    }
  }
}

///|
pub fn EnvTable::entries(self : EnvTable) -> Array[(String, String)] {
  self.ordered.map(fn(key) { (key, self.values[self.canonical_key(key)]) })
}

///|
pub fn EnvTable::keys(self : EnvTable) -> Array[String] {
  self.ordered.copy()
}

///|
pub fn[T : @host.HostEnv] snapshot(
  host : T,
  name_mode? : EnvNameMode = Sensitive,
) -> EnvTable raise @host.HostError {
  EnvTable::from_entries(@host.HostEnv::env_entries(host)[:], name_mode~)
}
