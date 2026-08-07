///|
#cfg(platform="windows")
priv struct NativeTestPath(String)

///|
#cfg(not(platform="windows"))
priv struct NativeTestPath(Bytes)

///|
#cfg(platform="windows")
fn NativeTestPath::new(value : String) -> NativeTestPath {
  NativeTestPath(value)
}

///|
#cfg(not(platform="windows"))
fn NativeTestPath::new(value : String) -> NativeTestPath {
  NativeTestPath(@utf8.encode(value))
}

///|
#borrow(path)
extern "C" fn set_readonly_for_test(
  path : NativeTestPath,
  make_readonly : Bool,
) -> Int = "moonjust_host_set_readonly_for_test"

///|
#borrow(target, link_path)
extern "C" fn symlink_for_test(
  target : NativeTestPath,
  link_path : NativeTestPath,
) -> Int = "moonjust_host_symlink_for_test"

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

///|
test "native filesystem commits same-directory transactions without debris" {
  let host = NativeFs::new()
  let target = @path.PathValue::new(
    ".moonjust-native-\u{6587}\u{4ef6}-transaction",
    Unix,
  )
  if @host.HostFs::file_exists(host, target) {
    @fs.remove_file(target.as_string())
  }
  @host.HostFs::write_file(host, target, b"old\r\n")
  @host.write_file_atomic(host, target, b"new\r\n")
  assert_eq(@host.HostFs::read_file(host, target), b"new\r\n")
  assert_eq(
    set_readonly_for_test(NativeTestPath::new(target.as_string()), true),
    0,
  )
  try @host.write_file_atomic(host, target, b"forbidden") catch {
    PermissionDenied(FsWrite, ..) => ()
    error => fail("unexpected readonly error: \{Repr(error)}")
  } noraise {
    _ => fail("expected readonly target rejection")
  }
  assert_eq(@host.HostFs::read_file(host, target), b"new\r\n")
  assert_eq(
    set_readonly_for_test(NativeTestPath::new(target.as_string()), false),
    0,
  )
  try @host.write_file_atomic(host, target, b"lost", overwrite=false) catch {
    AlreadyExists(path) => assert_eq(path, target)
    error => fail("unexpected no-overwrite error: \{Repr(error)}")
  } noraise {
    _ => fail("expected no-overwrite rejection")
  }
  assert_eq(@host.HostFs::read_file(host, target), b"new\r\n")
  let debris = @host.HostFs::read_dir(host, @path.PathValue::new(".", Unix)).filter(name => {
      name.has_prefix(".moonjust.tmp.")
    },
  )
  assert_eq(debris, [])
  @fs.remove_file(target.as_string())
}

///|
test "native canonical identity follows filesystem symlinks" {
  let host = NativeFs::new()
  let target = @path.PathValue::new(".moonjust-native-symlink-target", Unix)
  let link = @path.PathValue::new(".moonjust-native-symlink", Unix)
  if @host.HostFs::file_exists(host, link) {
    @fs.remove_file(link.as_string())
  }
  if @host.HostFs::file_exists(host, target) {
    @fs.remove_file(target.as_string())
  }
  @host.HostFs::write_file(host, target, b"target")
  assert_eq(
    symlink_for_test(
      NativeTestPath::new(target.as_string()),
      NativeTestPath::new(link.as_string()),
    ),
    0,
  )
  assert_eq(
    @host.HostFs::canonicalize(host, link),
    @host.HostFs::canonicalize(host, target),
  )
  @fs.remove_file(link.as_string())
  @fs.remove_file(target.as_string())
}

///|
test "native environment adapter exposes deterministic snapshots and cwd" {
  let host = NativeFs::new()
  let entries = @host.HostEnv::env_entries(host)
  for index in 1..<entries.length() {
    let left = entries[index - 1].0
    let right = entries[index].0
    let length = Int::min(left.length(), right.length())
    let mut order = 0
    for offset in 0..<length {
      order = left.unsafe_get(offset).compare(right.unsafe_get(offset))
      if order != 0 {
        break
      }
    }
    if order == 0 {
      order = left.length().compare(right.length())
    }
    assert_true(order <= 0)
  }
  let cwd = @host.HostEnv::current_dir(host)
  assert_true(cwd.as_string() != "")
}
