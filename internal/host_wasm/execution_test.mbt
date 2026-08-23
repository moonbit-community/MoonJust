///|
async test "wasm execution cache store uses the shared manifest contract" {
  let directory = try! @path.PathValue::new(
    "_build/wasm-cache-store-test",
    Unix,
  )
  try @async_fs.rmdir(directory.as_string(), recursive=true) catch {
    _ => ()
  } noraise {
    _ => ()
  }
  let host = ExecutionFs::new()
  let digest = "b".repeat(64)
  let lease = @host.HostCacheStore::acquire_cache_lease(host, directory, digest)
  assert_eq(@host.HostCacheStore::read_cache_manifest(host, lease), None)
  let forged = @host.CacheLease::new(directory, "c".repeat(64), lease.token())
  try @host.HostCacheStore::read_cache_manifest(host, forged) catch {
    InvalidInput(_) => ()
    error => fail("unexpected forged lease error: \{Repr(error)}")
  } noraise {
    _ => fail("expected forged lease rejection")
  }
  @host.HostCacheStore::write_cache_manifest(host, lease, b"manifest")
  @host.HostCacheStore::release_cache_lease(host, lease)
  let stale = try! directory.join(
    try! @path.PathValue::new("." + digest + ".tmp", Unix),
  )
  let unrelated_temporary = try! directory.join(
    try! @path.PathValue::new("." + digest + ".not-owned.tmp", Unix),
  )
  @async_fs.write_file(
    stale.as_string(),
    b"stale",
    create_mode=CreateOrTruncate,
  )
  @async_fs.write_file(
    unrelated_temporary.as_string(),
    b"keep",
    create_mode=CreateOrTruncate,
  )
  let next = @host.HostCacheStore::acquire_cache_lease(host, directory, digest)
  assert_false(@host.HostFs::file_exists(host, stale))
  assert_true(@host.HostFs::file_exists(host, unrelated_temporary))
  assert_eq(
    @host.HostCacheStore::read_cache_manifest(host, next),
    Some(b"manifest"),
  )
  @host.HostCacheStore::release_cache_lease(host, next)
  let manifest_path = try! directory.join(
    try! @path.PathValue::new(digest + ".json", Unix),
  )
  @async_fs.write_file(
    manifest_path.as_string(),
    @utf8.encode("x".repeat(@cache.MAX_MANIFEST_BYTES + 64)),
    create_mode=CreateOrTruncate,
  )
  let bounded = @host.HostCacheStore::acquire_cache_lease(
    host, directory, digest,
  )
  guard @host.HostCacheStore::read_cache_manifest(host, bounded) is Some(bytes) else {
    fail("expected oversized manifest prefix")
  }
  assert_eq(bytes.length(), @cache.MAX_MANIFEST_BYTES + 1)
  @host.HostCacheStore::release_cache_lease(host, bounded)
  let orphan_temporary = try! directory.join(
    try! @path.PathValue::new("." + "d".repeat(64) + ".tmp", Unix),
  )
  @async_fs.write_file(
    orphan_temporary.as_string(),
    b"orphan",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@host.HostCacheStore::clean_cache(host, directory, None), 1)
  assert_false(@host.HostFs::file_exists(host, orphan_temporary))
  assert_true(@host.HostFs::file_exists(host, unrelated_temporary))
  try @async_fs.rmdir(directory.as_string(), recursive=true) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
async test "wasm execution filesystem commits policy-checked atomic writes" {
  let directory = try! @path.PathValue::new(
    "_build/wasm-atomic-write-test",
    Unix,
  )
  try @async_fs.rmdir(directory.as_string(), recursive=true) catch {
    _ => ()
  } noraise {
    _ => ()
  }
  @async_fs.mkdir(directory.as_string(), recursive=true)
  let target = try! directory.join(try! @path.PathValue::new("justfile", Unix))
  let host = ExecutionFs::new()
  @host.HostAtomicFs::write_file_atomic(host, target, b"first", false)
  assert_eq(@host.HostFs::read_file(host, target), b"first")
  try
    @host.HostAtomicFs::write_file_atomic(host, target, b"lost", false)
  catch {
    AlreadyExists(path) => assert_eq(path, target)
    error => fail("unexpected atomic write error: \{Repr(error)}")
  } noraise {
    _ => fail("expected no-overwrite transaction to reject existing target")
  }
  assert_eq(@host.HostFs::read_file(host, target), b"first")
  for name in @host.HostFs::read_dir(host, directory) {
    assert_false(name.has_prefix(".moonjust.tmp."))
  }
  @host.HostAtomicFs::write_file_atomic(host, target, b"second", true)
  assert_eq(@host.HostFs::read_file(host, target), b"second")
  try @async_fs.rmdir(directory.as_string(), recursive=true) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
async test "wasm execution filesystem delegates reads and owns script cleanup" {
  let directory = try! @path.PathValue::new(
    "_build/wasm-execution-lifecycle-test",
    Unix,
  )
  try @async_fs.rmdir(directory.as_string(), recursive=true) catch {
    _ => ()
  } noraise {
    _ => ()
  }
  @async_fs.mkdir(directory.as_string(), recursive=true)
  let host = ExecutionFs::new()
  let module_path = try! @path.PathValue::new("moon.mod", Unix)
  let contents = @host.HostFs::read_file(host, module_path)
  assert_eq(
    @host.HostSourceReader::read_source(host, module_path, 6),
    contents[:7].to_owned(),
  )
  assert_eq(
    @host.HostFs::read_file_range(host, module_path, 1L, 5),
    contents[1:6].to_owned(),
  )
  assert_true(@host.HostFs::file_exists(host, module_path))
  assert_true(
    @host.HostFs::read_dir(host, try! @path.PathValue::new(".", Unix)).contains(
      "moon.mod",
    ),
  )
  assert_eq(
    @host.HostFs::metadata(host, module_path).size(),
    contents.length().to_int64(),
  )
  assert_true(
    @host.HostFs::canonicalize(host, module_path)
    .as_string()
    .has_suffix("moon.mod"),
  )
  try @host.HostFs::write_file(host, module_path, b"denied") catch {
    CapabilityDenied(FsWrite) => ()
    error => fail("unexpected write denial: \{Repr(error)}")
  } noraise {
    _ => fail("expected ordinary writes to be denied")
  }
  try
    @host.HostFs::persist_temp_file(host, module_path, module_path, true)
  catch {
    CapabilityDenied(FsWrite) => ()
    error => fail("unexpected persist denial: \{Repr(error)}")
  } noraise {
    _ => fail("expected temp persistence to be denied")
  }
  try
    @host.HostTemp::create_temp_file(host, directory, "temp", b"denied")
  catch {
    CapabilityDenied(FsWrite) => ()
    error => fail("unexpected temp creation denial: \{Repr(error)}")
  } noraise {
    _ => fail("expected temp creation to be denied")
  }
  try @host.HostTemp::remove_temp_file(host, module_path) catch {
    CapabilityDenied(FsWrite) => ()
    error => fail("unexpected temp removal denial: \{Repr(error)}")
  } noraise {
    _ => fail("expected temp removal to be denied")
  }
  let plain = @host.HostAsyncScriptTemp::create_script_temp_async(
    host, directory, "script", ".txt", b"plain", false,
  )
  assert_eq(@host.HostFs::read_file(host, plain), b"plain")
  @host.HostAsyncScriptTemp::remove_script_temp_async(host, plain)
  assert_false(@host.HostFs::file_exists(host, plain))
  @host.HostAsyncScriptTemp::remove_script_temp_async(host, plain)
  let executable = @host.HostAsyncScriptTemp::create_script_temp_async(
    host, directory, "script", ".sh", b"#!/bin/sh\n", true,
  )
  assert_eq(@host.HostFs::read_file(host, executable), b"#!/bin/sh\n")
  @host.HostAsyncScriptTemp::remove_script_temp_async(host, executable)
  for name in [("", ".sh"), ("bad/name", ".sh"), ("ok", "/bad")] {
    let (stem, extension) = name
    try
      @host.HostAsyncScriptTemp::create_script_temp_async(
        host, directory, stem, extension, b"denied", false,
      )
    catch {
      InvalidInput(_) => ()
      error => fail("unexpected script name error: \{Repr(error)}")
    } noraise {
      _ => fail("expected invalid script name rejection")
    }
  }
  let missing = try! @path.PathValue::new(
    "_build/wasm-execution-lifecycle-test-missing",
    Unix,
  )
  try
    @host.HostAsyncScriptTemp::create_script_temp_async(
      host, missing, "script", ".sh", b"denied", false,
    )
  catch {
    InvalidInput(_) => ()
    error => fail("unexpected missing directory error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing directory rejection")
  }
  try @async_fs.rmdir(directory.as_string(), recursive=true) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}
