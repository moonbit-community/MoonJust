///|
fn test_host() -> FakeHost raise @path.PathError {
  let cwd = @path.PathValue::new("/workspace", Unix)
  FakeHost::new(cwd, @host.PlatformInfo::new(Linux, "test", Unix))
}

///|
test "fake host preserves filesystem and environment capabilities" {
  let host = test_host()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"build:\n")
  assert_eq(@host.HostFs::read_file(host, file), b"build:\n")
  assert_true(@host.HostFs::file_exists(host, file))
  host.set_env("MODE", "test")
  assert_eq(@host.HostEnv::env_get(host, "MODE"), Some("test"))
  assert_eq(
    @host.HostEnv::current_dir(host),
    @path.PathValue::new("/workspace", Unix),
  )
}

///|
test "fake host exposes typed capability denial" {
  let host = test_host()
  host.deny(FsRead)
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  try @host.HostFs::read_file(host, file) catch {
    CapabilityDenied(FsRead) => ()
    error => fail("unexpected host error: \{Repr(error)}")
  } noraise {
    _ => fail("expected capability denial")
  }
}
