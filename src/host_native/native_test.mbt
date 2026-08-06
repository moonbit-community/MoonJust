///|
test "real filesystem adapter reads metadata directories and canonical identity" {
  let host = NativeFs::new()
  let path = @path.PathValue::new("moon.mod", Unix)
  assert_true(@host.HostFs::file_exists(host, path))
  let bytes = @host.HostFs::read_file(host, path)
  assert_true(bytes.length() > 0)
  let metadata = @host.HostFs::metadata(host, path)
  assert_true(metadata.is_file())
  assert_eq(metadata.size(), bytes.length().to_int64())
  let directory = @host.HostFs::read_dir(host, @path.PathValue::new(".", Unix))
  assert_true(directory.contains("moon.mod"))
  let canonical = @host.HostFs::canonicalize(host, path)
  assert_true(canonical.as_string().has_suffix("moon.mod"))
}
