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
