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
  assert_eq(
    @host.HostFs::read_file_range(host, path, 0L, 7),
    bytes[:7].to_owned(),
  )
  let total = Ref(0L)
  let max_chunk = Ref(0)
  @host.stream_file(host, path, chunk_size=11, fn(chunk) {
    total.val += chunk.length().to_int64()
    max_chunk.val = Int::max(max_chunk.val, chunk.length())
  })
  assert_eq(total.val, metadata.size())
  assert_true(max_chunk.val <= 11)
  let directory = @host.HostFs::read_dir(host, @path.PathValue::new(".", Unix))
  assert_true(directory.contains("moon.mod"))
  let canonical = @host.HostFs::canonicalize(host, path)
  assert_true(canonical.as_string().has_suffix("moon.mod"))
}
