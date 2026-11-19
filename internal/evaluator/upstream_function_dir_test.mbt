///|
test "upstream function::tests::dir_not_found" {
  try eval_upstream_context_function("runtime_directory()") catch {
    error => assert_eq(error.message(), "runtime directory not found")
  } noraise {
    _ => fail("expected a missing runtime directory")
  }
}
