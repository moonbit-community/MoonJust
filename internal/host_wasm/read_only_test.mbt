///|
test "read-only adapter reads and ranges but always denies writes" {
  let host = @host_wasm.ReadOnlyFs::new()
  let path = @path.PathValue::new("moon.mod", Unix)
  let contents = @host.HostFs::read_file(host, path)
  assert_true(contents.length() > 7)
  assert_eq(
    @host.HostFs::read_file_range(host, path, 0L, 7),
    contents[:7].to_owned(),
  )
  assert_eq(
    @host.HostFs::metadata(host, path).size(),
    contents.length().to_int64(),
  )
  try @host.HostFs::write_file(host, path, b"denied") catch {
    CapabilityDenied(FsWrite) => ()
    error => fail("unexpected write error: \{Repr(error)}")
  } noraise {
    _ => fail("expected read-only adapter to deny writes")
  }
  try @host.write_file_atomic(host, path, b"denied") catch {
    CapabilityDenied(FsWrite) => ()
    error => fail("unexpected atomic write error: \{Repr(error)}")
  } noraise {
    _ => fail("expected read-only adapter to deny atomic writes")
  }
}
