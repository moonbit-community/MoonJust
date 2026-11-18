///|
async test "range reads preserve bytes, short reads and 64-bit EOF; source reads stop at the limit plus one" {
  let host = ExecutionFs::new()
  let name = ".moonjust-range-" + execution_suffix()
  let path = @path.PathValue::new(name, host.current_dir().flavor())
  @async_fs.write_binary(name, b"a\x00\xffz", create_mode=CreateNew)
  defer @async_fs.remove(name)
  assert_eq(host.file_size(path), 4L)
  assert_eq(host.read_file_range(path, 1L, 2), b"\x00\xff")
  assert_eq(host.read_file_range(path, 3L, 8), b"z")
  assert_eq(host.read_file_range(path, 0x100000000L, 8), b"")
  assert_eq(host.read_file_range(path, 1L, 0), b"")
  assert_eq(host.read_source(path, 1), b"a\x00")
}

///|
async test "upstream format::write_error" {
  let host = ExecutionFs::new()
  let dir = @async_fs.tmpdir(prefix="moonjust atomic")
  defer @async_fs.remove(dir, recursive=true)
  let path = @path.PathValue::new(
    dir + "/justfile",
    host.current_dir().flavor(),
  )
  let original = b"x    :=    'hello'   "
  @async_fs.write_binary(path.as_string(), original, permission=0o755)
  let executable = host.can_execute(path)
  try host.write_file_atomic(path, b"x := 'hello'\n", true) catch {
    InvalidInput(detail) =>
      assert_eq(
        detail, "cannot atomically replace an existing file and preserve its permissions",
      )
    error => fail("unexpected host error: \{Repr(error)}")
  } noraise {
    _ => fail("expected a refused replacement")
  }
  try host.write_file_atomic(path, b"new", false) catch {
    AlreadyExists(_) => ()
    error => fail("unexpected host error: \{Repr(error)}")
  } noraise {
    _ => fail("expected exclusive creation")
  }
  assert_eq(@async_fs.read_binary(path.as_string()), original)
  assert_eq(host.can_execute(path), executable)
}
