///|
fn assert_invalid_override(path : String) -> Unit raise {
  try VariableOverride::parse(path, "bar") catch {
    InvalidOverridePath(path=actual) => assert_eq(actual, path)
    error => fail("unexpected override error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid override path")
  }
}

///|
test "upstream overrides::invalid_override_path_positional" {
  assert_invalid_override("0::foo")
}

///|
test "upstream overrides::invalid_override_path_set" {
  assert_invalid_override("0::foo")
}
