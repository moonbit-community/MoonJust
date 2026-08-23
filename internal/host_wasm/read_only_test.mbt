///|
async test "read-only adapter reads and ranges but always denies writes" {
  let host = @host_wasm.ReadOnlyFs::new()
  let path = @path.PathValue::new("moon.mod", Unix)
  let contents = @host.HostFs::read_file(host, path)
  assert_true(contents.length() > 7)
  assert_eq(
    @host.HostSourceReader::read_source(host, path, 7),
    contents[:8].to_owned(),
  )
  assert_eq(
    @host.HostFs::read_file_range(host, path, 0L, 7),
    contents[:7].to_owned(),
  )
  assert_eq(@host.HostFs::read_file_range(host, path, 2L, 0), b"")
  assert_eq(
    @host.HostFs::read_file_range(host, path, contents.length().to_int64(), 7),
    b"",
  )
  for range in [(-1L, 1), (0L, -1), (0x8000_0000L, 1)] {
    let (offset, length) = range
    try @host.HostFs::read_file_range(host, path, offset, length) catch {
      InvalidInput(_) => ()
      error => fail("unexpected range error: \{Repr(error)}")
    } noraise {
      _ => fail("expected invalid range rejection")
    }
  }
  assert_true(@host.HostFs::file_exists(host, path))
  assert_true(
    @host.HostFs::read_dir(host, @path.PathValue::new(".", Unix)).contains(
      "moon.mod",
    ),
  )
  assert_eq(
    @host.HostFs::metadata(host, path).size(),
    contents.length().to_int64(),
  )
  assert_true(
    @host.HostFs::canonicalize(host, path).as_string().has_suffix("moon.mod"),
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
  try @host.HostFs::persist_temp_file(host, path, path, true) catch {
    CapabilityDenied(FsWrite) => ()
    error => fail("unexpected persist error: \{Repr(error)}")
  } noraise {
    _ => fail("expected read-only adapter to deny temp persistence")
  }
  let root = try! @path.PathValue::new(".", Unix)
  try @host.HostTemp::create_temp_file(host, root, "temp", b"denied") catch {
    CapabilityDenied(FsWrite) => ()
    error => fail("unexpected temp creation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected read-only adapter to deny temp creation")
  }
  try @host.HostTemp::remove_temp_file(host, path) catch {
    CapabilityDenied(FsWrite) => ()
    error => fail("unexpected temp removal error: \{Repr(error)}")
  } noraise {
    _ => fail("expected read-only adapter to deny temp removal")
  }
}
