///|
#derive(Eq, Debug)
pub(all) enum BuiltinTarget {
  Native
  Wasm1
}

///|
/// Backend inventory retained for registry inspection.
pub fn BuiltinSpec::targets(_self : BuiltinSpec) -> ArrayView[BuiltinTarget] {
  [Native, Wasm1]
}

///|
pub fn BuiltinSpec::evidence(self : BuiltinSpec) -> String {
  "just-1.59.0/" + self.name
}
