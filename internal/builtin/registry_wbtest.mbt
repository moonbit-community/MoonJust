///|
test "canonical and alias lookups cover the ordered builtin inventory" {
  let spellings : Set[String] = Set([])
  assert_eq(registry().map(spec => spec.name()), names().to_owned())
  for spec in registry() {
    for spelling in [spec.name(), ..spec.aliases()] {
      assert_false(spellings.contains(spelling))
      spellings.add(spelling)
      assert_eq(find(spelling), Some(spec))
      assert_eq(canonical_name(spelling), spec.name())
      assert_eq(is_effectful(spelling), spec.purity() is Effect)
    }
  }
  assert_true(find("unknown_dir_native") is None)
  let directory = find("invocation_dir_native").unwrap()
  assert_eq(directory.capabilities(), [Context])
  assert_true(directory.accepts_arity(0))
  assert_false(directory.accepts_arity(1))
  assert_eq(directory.evidence(), "just-1.59.0/invocation_directory_native")
}
