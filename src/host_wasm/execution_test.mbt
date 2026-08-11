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
    try! @path.PathValue::new(
      "." + digest + "." + "2".repeat(24) + ".tmp",
      Unix,
    ),
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
  assert_eq(@host.HostCacheStore::clean_cache(host, directory, None), 1)
  try @async_fs.rmdir(directory.as_string(), recursive=true) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}
