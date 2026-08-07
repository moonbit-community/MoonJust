///|
async test "policy filesystem atomically replaces bytes and cleans failures" {
  let host = PolicyFs::new()
  let directory = @path.PathValue::new("_build", Unix)
  let target = @path.PathValue::new("_build/moonjust-wasm-transaction", Unix)
  if @host.HostFs::file_exists(host, target) {
    @async_fs.remove(target.as_string())
  }
  @host.HostFs::write_file(host, target, b"old\r\n")
  @host.HostAtomicFs::write_file_atomic(host, target, b"new\r\n", true)
  assert_eq(@host.HostFs::read_file(host, target), b"new\r\n")
  try
    @host.HostAtomicFs::write_file_atomic(host, target, b"lost", false)
  catch {
    AlreadyExists(actual) => assert_eq(actual, target)
    error => fail("unexpected no-overwrite error: \{Repr(error)}")
  } noraise {
    _ => fail("expected no-overwrite rejection")
  }
  assert_eq(@host.HostFs::read_file(host, target), b"new\r\n")
  let debris = @host.HostFs::read_dir(host, directory).filter(name => {
    name.has_prefix(".moonjust.tmp.")
  })
  assert_eq(debris, [])
  @async_fs.remove(target.as_string())
}
