///|
fn format_test_host() -> @host_testkit.FakeHost raise @path.PathError {
  let cwd = @path.PathValue::new("/workspace", Unix)
  @host_testkit.FakeHost::new(cwd, @host.PlatformInfo::new(Linux, "test", Unix))
}

///|
test "upstream format::write_error" {
  let host = format_test_host()
  let path = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(path, b"x    :=    'hello'   ")
  host.fail_next_persist()
  try write_file_atomic(host, path, b"x := 'hello'\n") catch {
    InvalidInput(detail) => assert_eq(detail, "injected atomic persist failure")
    error => fail("unexpected host error: \{Repr(error)}")
  } noraise {
    _ => fail("expected atomic write failure")
  }
  assert_eq(@host.HostFs::read_file(host, path), b"x    :=    'hello'   ")
}
