///|
#cfg(platform="windows")
#borrow(path)
extern "C" fn test_file_attributes(path : String) -> UInt = "GetFileAttributesW"

///|
#cfg(platform="windows")
#borrow(path)
extern "C" fn test_set_file_attributes(path : String, attributes : UInt) -> Int = "SetFileAttributesW"

///|
#cfg(not(platform="windows"))
#borrow(path)
extern "C" fn test_chmod(path : Bytes, mode : Int) -> Int = "chmod"

///|
#cfg(not(platform="windows"))
#borrow(path, metadata)
extern "C" fn test_stat(path : Bytes, metadata : Bytes) -> Int = "stat"

///|
#cfg(not(platform="windows"))
#borrow(path)
extern "C" fn test_mkfifo(path : Bytes, mode : Int) -> Int = "mkfifo"

///|
#cfg(platform="windows")
fn make_fifo_for_test(_path : String) -> Int {
  -1
}

///|
#cfg(not(platform="windows"))
fn make_fifo_for_test(path : String) -> Int {
  test_mkfifo(@utf8.encode(path) + Bytes::make(1, (0).to_byte()), 0o600)
}

///|
#cfg(platform="windows")
fn set_readonly_for_test(path : @path.PathValue, make_readonly : Bool) -> Int {
  let value = test_file_attributes(path.as_string())
  if value == 4294967295U {
    3
  } else {
    let next = if make_readonly { value | 1U } else { value & 4294967294U }
    if test_set_file_attributes(path.as_string(), next) != 0 {
      0
    } else {
      4
    }
  }
}

///|
#cfg(not(platform="windows"))
fn set_readonly_for_test(path : @path.PathValue, make_readonly : Bool) -> Int {
  if test_chmod(
      @utf8.encode(path.as_string()) + Bytes::make(1, (0).to_byte()),
      if make_readonly {
        0o400
      } else {
        0o600
      },
    ) ==
    0 {
    0
  } else {
    4
  }
}

///|
#cfg(not(platform="windows"))
fn set_mode_for_test(path : @path.PathValue, mode : Int) -> Int {
  if test_chmod(
      @utf8.encode(path.as_string()) + Bytes::make(1, (0).to_byte()),
      mode,
    ) ==
    0 {
    0
  } else {
    4
  }
}

///|
#cfg(not(platform="windows"))
fn mode_for_test(path : @path.PathValue) -> Int? {
  let metadata = Bytes::make(512, 0)
  let value = @utf8.encode(path.as_string()) + Bytes::make(1, (0).to_byte())
  if test_stat(value, metadata) != 0 {
    None
  } else {
    let host = NativeFs::new()
    let offset = try {
      if @host.HostPlatform::platform_info(host).operating_system() == Macos {
        4
      } else {
        24
      }
    } catch {
      _ => 24
    }
    Some(
      (metadata[offset].to_int() | (metadata[offset + 1].to_int() << 8)) &
      0o7777,
    )
  }
}

///|
#cfg(platform="windows")
fn set_mode_for_test(_path : @path.PathValue, _mode : Int) -> Int {
  0
}

///|
#cfg(platform="windows")
fn mode_for_test(_path : @path.PathValue) -> Int? {
  None
}

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
async test "native source reader retains at most limit plus one byte" {
  let host = NativeFs::new()
  let path = @path.PathValue::new(".moonjust-native-bounded-source", Unix)
  @host.HostFs::write_file(host, path, b"")
  assert_eq(@host.HostSourceReader::read_source(host, path, 4), b"")
  @host.HostFs::write_file(host, path, b"0123")
  assert_eq(@host.HostSourceReader::read_source(host, path, 4), b"0123")
  @host.HostFs::write_file(host, path, b"01234")
  assert_eq(@host.HostSourceReader::read_source(host, path, 4), b"01234")
  @host.HostFs::write_file(host, path, b"0123456789abcdef")
  assert_eq(@host.HostSourceReader::read_source(host, path, 4), b"01234")
  assert_eq(@host.HostSourceReader::read_source(host, path, 0), b"0")
  @fs.remove_file(path.as_string())
}

///|
async test "native source reader streams named pipes" {
  if @host.HostPlatform::platform_info(NativeFs::new()).operating_system() ==
    Windows {
    return
  }
  @async.with_task_group() <| group => {
    let host = NativeFs::new()
    let path = @path.PathValue::new(".moonjust-native-dotenv-fifo", Unix)
    if @fs.path_exists(path.as_string()) {
      @fs.remove_file(path.as_string())
    }
    assert_eq(make_fifo_for_test(path.as_string()), 0)
    group.add_defer(() => @fs.remove_file(path.as_string()))
    assert_true(@host.HostFs::file_exists(host, path))
    let metadata = @host.HostFs::metadata(host, path)
    assert_false(metadata.is_file())
    assert_false(metadata.is_directory())
    group.spawn_bg() <| () => {
      let writer = @async_fs.open(path.as_string(), mode=WriteOnly)
      defer writer.close()
      writer.write(b"DOTENV_KEY=foo\n")
    }
    assert_eq(
      @host.HostSourceReader::read_source(host, path, 1024),
      b"DOTENV_KEY=foo\n",
    )
  }
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
  assert_eq(set_mode_for_test(target, 0o640), 0)
  @host.write_file_atomic(host, target, b"new\r\n")
  assert_eq(@host.HostFs::read_file(host, target), b"new\r\n")
  if mode_for_test(target) is Some(mode) {
    assert_eq(mode, 0o640)
  }
  assert_eq(set_readonly_for_test(target, true), 0)
  try @host.write_file_atomic(host, target, b"forbidden") catch {
    PermissionDenied(FsWrite, ..) => ()
    error => fail("unexpected readonly error: \{Repr(error)}")
  } noraise {
    _ => fail("expected readonly target rejection")
  }
  assert_eq(@host.HostFs::read_file(host, target), b"new\r\n")
  assert_eq(set_readonly_for_test(target, false), 0)
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
async test "native canonical identity follows filesystem symlinks" {
  let host = NativeFs::new()
  let flavor = @host.HostPlatform::platform_info(host).path_flavor()
  let separator = "\{flavor.separator()}"
  let cwd = @host.HostEnv::current_dir(host).as_string()
  let target = @path.PathValue::new(
    cwd + separator + ".moonjust-native-symlink-target",
    flavor,
  )
  let link = @path.PathValue::new(
    cwd + separator + ".moonjust-native-symlink",
    flavor,
  )
  @async.with_task_group() <| group => {
    if @host.HostFs::file_exists(host, link) {
      @async_fs.remove(link.as_string())
    }
    if @host.HostFs::file_exists(host, target) {
      @async_fs.rmdir(target.as_string(), recursive=true)
    }
    @async_fs.mkdir(target.as_string())
    @async_fs.symlink(link.as_string(), target=target.as_string())
    group.add_defer(() => @async_fs.remove(link.as_string()))
    group.add_defer(() => @async_fs.rmdir(target.as_string(), recursive=true))
    assert_eq(
      @host.HostFs::canonicalize(host, link),
      @host.HostFs::canonicalize(host, target),
    )
  }
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

///|
test "native platform and terminal adapter reports real target facts" {
  let host = NativeFs::new()
  let platform = @host.HostPlatform::platform_info(host)
  assert_true(
    platform.operating_system() == Linux ||
    platform.operating_system() == Macos ||
    platform.operating_system() == Windows ||
    platform.operating_system() == Other("native"),
  )
  assert_true(platform.architecture() != "unknown")
  assert_eq(
    platform.path_flavor(),
    if platform.operating_system() == Windows {
      Windows
    } else {
      Unix
    },
  )
  let terminal = @host.HostTerminal::terminal_info(host)
  ignore(terminal)
}

///|
async test "cache store serializes leases commits atomically and cleans manifests" {
  let directory = try! @path.PathValue::new(
    "_build/native-cache-store-test",
    Unix,
  )
  try @async_fs.rmdir(directory.as_string(), recursive=true) catch {
    _ => ()
  } noraise {
    _ => ()
  }
  let host = NativeFs::new()
  let digest = "a".repeat(64)
  let first = try
    @host.HostCacheStore::acquire_cache_lease(host, directory, digest)
  catch {
    error => fail("first cache lease failed: \{Repr(error)}")
  } noraise {
    value => value
  }
  assert_eq(@host.HostCacheStore::read_cache_manifest(host, first), None)
  let forged = @host.CacheLease::new(directory, "c".repeat(64), first.token())
  try @host.HostCacheStore::read_cache_manifest(host, forged) catch {
    InvalidInput(_) => ()
    error => fail("unexpected forged lease error: \{Repr(error)}")
  } noraise {
    _ => fail("expected forged lease rejection")
  }
  let second_acquired = Ref(false)
  @async.with_task_group() <| group => {
    let waiter = group.spawn(() => {
      let second = try
        @host.HostCacheStore::acquire_cache_lease(host, directory, digest)
      catch {
        error => fail("second cache lease failed: \{Repr(error)}")
      } noraise {
        value => value
      }
      second_acquired.val = true
      try @host.HostCacheStore::release_cache_lease(host, second) catch {
        error => fail("second cache release failed: \{Repr(error)}")
      } noraise {
        _ => ()
      }
    })
    @async.sleep(10)
    assert_false(second_acquired.val)
    try
      @host.HostCacheStore::write_cache_manifest(host, first, b"manifest")
    catch {
      error => fail("cache manifest write failed: \{Repr(error)}")
    } noraise {
      _ => ()
    }
    try @host.HostCacheStore::release_cache_lease(host, first) catch {
      error => fail("first cache release failed: \{Repr(error)}")
    } noraise {
      _ => ()
    }
    waiter.wait()
  }
  assert_true(second_acquired.val)
  let stale = try! directory.join(
    try! @path.PathValue::new("." + digest + ".tmp", Unix),
  )
  let unrelated_temporary = try! directory.join(
    try! @path.PathValue::new("." + digest + ".not-owned.tmp", Unix),
  )
  for path in [stale, unrelated_temporary] {
    @async_fs.write_file(
      path.as_string(),
      b"stale",
      create_mode=CreateOrTruncate,
    )
  }
  let third = try
    @host.HostCacheStore::acquire_cache_lease(host, directory, digest)
  catch {
    error => fail("third cache lease failed: \{Repr(error)}")
  } noraise {
    value => value
  }
  assert_false(@host.HostFs::file_exists(host, stale))
  assert_true(@host.HostFs::file_exists(host, unrelated_temporary))
  assert_eq(
    @host.HostCacheStore::read_cache_manifest(host, third),
    Some(b"manifest"),
  )
  try @host.HostCacheStore::release_cache_lease(host, third) catch {
    error => fail("third cache release failed: \{Repr(error)}")
  } noraise {
    _ => ()
  }
  let manifest_path = try! directory.join(
    try! @path.PathValue::new(digest + ".json", Unix),
  )
  @async_fs.write_file(
    manifest_path.as_string(),
    @utf8.encode("x".repeat(@cache.MAX_MANIFEST_BYTES + 64)),
    create_mode=CreateOrTruncate,
  )
  let bounded = try! @host.HostCacheStore::acquire_cache_lease(
    host, directory, digest,
  )
  let bounded_contents = try! @host.HostCacheStore::read_cache_manifest(
    host, bounded,
  )
  guard bounded_contents is Some(bytes) else {
    fail("expected oversized manifest prefix")
  }
  assert_eq(bytes.length(), @cache.MAX_MANIFEST_BYTES + 1)
  try! @host.HostCacheStore::release_cache_lease(host, bounded)
  let keep = try! directory.join(try! @path.PathValue::new("keep.txt", Unix))
  let orphan_digest = "d".repeat(64)
  let orphan_temporary = try! directory.join(
    try! @path.PathValue::new("." + orphan_digest + ".tmp", Unix),
  )
  @async_fs.write_file(keep.as_string(), b"keep", create_mode=CreateOrTruncate)
  @async_fs.write_file(
    orphan_temporary.as_string(),
    b"orphan",
    create_mode=CreateOrTruncate,
  )
  let cleaned = try
    @host.HostCacheStore::clean_cache(host, directory, None)
  catch {
    error => fail("cache clean failed: \{Repr(error)}")
  } noraise {
    value => value
  }
  assert_eq(cleaned, 1)
  assert_true(@host.HostFs::file_exists(host, keep))
  assert_true(@host.HostFs::file_exists(host, unrelated_temporary))
  assert_false(@host.HostFs::file_exists(host, orphan_temporary))
  try @async_fs.rmdir(directory.as_string(), recursive=true) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
async test "native adapter covers bounded failures temporary lifecycles and host facts" {
  let host = NativeFs::new()
  let directory = try! @path.PathValue::new(
    "_build/native-host-lifecycle-test",
    Unix,
  )
  try @async_fs.rmdir(directory.as_string(), recursive=true) catch {
    _ => ()
  } noraise {
    _ => ()
  }
  @async_fs.mkdir(directory.as_string(), recursive=true)
  let source = try! directory.join(try! @path.PathValue::new("source", Unix))
  @host.HostFs::write_file(host, source, b"0123456789")
  assert_eq(@host.HostFs::read_file_range(host, source, 2L, 4), b"2345")
  assert_eq(@host.HostFs::read_file_range(host, source, 10L, 0), b"")
  for range in [(-1L, 1), (0L, -1)] {
    let (offset, length) = range
    try @host.HostFs::read_file_range(host, source, offset, length) catch {
      InvalidInput(_) => ()
      error => fail("unexpected native range error: \{Repr(error)}")
    } noraise {
      _ => fail("expected invalid native range rejection")
    }
  }
  for limit in [-1, 0x7fff_ffff] {
    try @host.HostSourceReader::read_source(host, source, limit) catch {
      InvalidInput(_) => ()
      error => fail("unexpected source limit error: \{Repr(error)}")
    } noraise {
      _ => fail("expected invalid source limit rejection")
    }
  }
  let missing = try! directory.join(try! @path.PathValue::new("missing", Unix))
  assert_false(@host.HostFs::file_exists(host, missing))
  try @host.HostFs::read_dir(host, missing) catch {
    NotFound(path) => assert_eq(path, missing)
    error => fail("unexpected missing directory error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing directory rejection")
  }
  try @host.HostFs::canonicalize(host, missing) catch {
    NotFound(path) => assert_eq(path, missing)
    error => fail("unexpected missing canonical error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing canonical rejection")
  }
  try @host.HostFs::metadata(host, missing) catch {
    NotFound(path) => assert_eq(path, missing)
    InvalidInput(_) => ()
    error => fail("unexpected missing metadata error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing metadata rejection")
  }
  let temporary = @host.HostTemp::create_temp_file(
    host, directory, ".temporary.", b"temporary",
  )
  assert_eq(@host.HostFs::read_file(host, temporary), b"temporary")
  let destination = try! directory.join(
    try! @path.PathValue::new("destination", Unix),
  )
  @host.HostFs::persist_temp_file(host, temporary, destination, false)
  assert_eq(@host.HostFs::read_file(host, destination), b"temporary")
  for prefix in ["", "bad/name", "bad\\name"] {
    try
      @host.HostTemp::create_temp_file(host, directory, prefix, b"denied")
    catch {
      InvalidInput(_) => ()
      error => fail("unexpected temp prefix error: \{Repr(error)}")
    } noraise {
      _ => fail("expected invalid temp prefix rejection")
    }
  }
  let first_script = @host.HostScriptTemp::create_script_temp(
    host, directory, "runner", ".sh", b"first",
  )
  let second_script = @host.HostScriptTemp::create_script_temp(
    host, directory, "runner", ".sh", b"second",
  )
  assert_true(first_script != second_script)
  @host.HostExecutable::set_executable(host, first_script)
  @host.HostScriptTemp::remove_script_temp(host, first_script)
  @host.HostScriptTemp::remove_script_temp(host, second_script)
  for name in [("", ".sh"), ("bad/name", ".sh"), ("ok", "/bad")] {
    let (stem, extension) = name
    try
      @host.HostScriptTemp::create_script_temp(
        host, directory, stem, extension, b"denied",
      )
    catch {
      InvalidInput(_) => ()
      error => fail("unexpected script name error: \{Repr(error)}")
    } noraise {
      _ => fail("expected invalid script name rejection")
    }
  }
  let plain = @host.HostAsyncScriptTemp::create_script_temp_async(
    host, directory, "async", ".txt", b"plain", false,
  )
  assert_eq(@host.HostFs::read_file(host, plain), b"plain")
  @host.HostAsyncScriptTemp::remove_script_temp_async(host, plain)
  let executable = @host.HostAsyncScriptTemp::create_script_temp_async(
    host, directory, "async", ".sh", b"executable", true,
  )
  assert_eq(@host.HostFs::read_file(host, executable), b"executable")
  @host.HostAsyncScriptTemp::remove_script_temp_async(host, executable)
  for name in [("", ".sh"), ("bad/name", ".sh"), ("ok", "/bad")] {
    let (stem, extension) = name
    try
      @host.HostAsyncScriptTemp::create_script_temp_async(
        host, directory, stem, extension, b"denied", false,
      )
    catch {
      InvalidInput(_) => ()
      error => fail("unexpected async script name error: \{Repr(error)}")
    } noraise {
      _ => fail("expected invalid async script name rejection")
    }
  }
  try
    @host.HostAsyncScriptTemp::create_script_temp_async(
      host, missing, "async", ".sh", b"denied", false,
    )
  catch {
    InvalidInput(_) => ()
    error => fail("unexpected missing async directory error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing async directory rejection")
  }
  assert_true(@host.HostClock::now_millis(host) > 0L)
  assert_eq(@host.HostRandom::random_bytes(host, 0), b"")
  assert_eq(@host.HostRandom::random_bytes(host, 8).length(), 8)
  try @host.HostRandom::random_bytes(host, -1) catch {
    InvalidInput(_) => ()
    error => fail("unexpected random count error: \{Repr(error)}")
  } noraise {
    _ => fail("expected negative random count rejection")
  }
  assert_eq(
    @host.HostEnv::env_get(host, "MOONJUST_TEST_ENV_MISSING_71DB"),
    None,
  )
  let platform = @host.HostPlatform::platform_info(host)
  assert_true(platform.pid().unwrap_or(0) > 0)
  assert_true(platform.num_cpus().unwrap_or(0) > 0)
  assert_true(platform.executable() is Some(_))
  try @async_fs.rmdir(directory.as_string(), recursive=true) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}
