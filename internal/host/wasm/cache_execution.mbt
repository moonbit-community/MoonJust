///|
let execution_cache_locks : Map[Int32, ExecutionCacheLock] = Map([])

///|
let execution_cache_token : Ref[Int32] = Ref(0)

///|
fn execution_cache_child(
  directory : @path.PathValue,
  name : String,
) -> @path.PathValue raise @host.HostError {
  let child = @path.PathValue::new(name, directory.flavor()) catch {
    _ => raise InvalidInput("invalid cache filename")
  }
  directory.join(child) catch {
    _ => raise InvalidInput("cache path flavor mismatch")
  }
}

///|
async fn clean_execution_cache_temporary(
  directory : @path.PathValue,
  digest : String,
) -> Unit raise @host.HostError {
  let path = execution_cache_child(directory, "." + digest + ".tmp")
  try @async_fs.remove(path.as_string()) catch {
    @os_error.OsError(NotFound, ..) => ()
    error => raise execution_cache_error(error)
  } noraise {
    _ => ()
  }
}

///|
fn next_execution_cache_token() -> Int32 {
  let mut token = execution_cache_token.val
  while execution_cache_locks.contains(token) {
    token += 1
  }
  execution_cache_token.val = token + 1
  token
}

///|
fn execution_cache_error(error : Error) -> @host.HostError {
  match error {
    @os_error.OsError(AccessDenied, ..) =>
      PermissionDenied(FsWrite, detail="cache filesystem permission denied")
    @os_error.OsError(NotFound, ..) => InvalidInput("cache path does not exist")
    _ => InvalidInput("cache filesystem operation failed: " + error.to_string())
  }
}

///|
pub impl @host.HostCacheStore for ExecutionFs with fn acquire_cache_lease(
  _self : ExecutionFs,
  directory : @path.PathValue,
  digest : String,
) -> @host.CacheLease raise @host.HostError {
  if !cache_hex(digest, 64) {
    raise InvalidInput("invalid cache digest")
  }
  let lock = open_execution_cache_lock(directory, digest) catch {
    error => raise execution_cache_error(error)
  }
  errdefer (@async.protect_from_cancel(() => release_execution_cache_lock(lock)) catch {
    _ => ()
  })
  clean_execution_cache_temporary(directory, digest)
  let token = next_execution_cache_token()
  execution_cache_locks[token] = lock
  @host.CacheLease::new(directory, digest, token)
}

///|
fn require_execution_cache_lease(
  lease : @host.CacheLease,
) -> ExecutionCacheLock raise @host.HostError {
  guard execution_cache_locks.get(lease.token()) is Some(lock) else {
    raise InvalidInput("cache lease is not held")
  }
  if lock.directory != lease.directory() || lock.digest != lease.digest() {
    raise InvalidInput("cache lease does not match cache key")
  }
  lock
}

///|
pub impl @host.HostCacheStore for ExecutionFs with fn read_cache_manifest(
  _self : ExecutionFs,
  lease : @host.CacheLease,
) -> Bytes? raise @host.HostError {
  ignore(require_execution_cache_lease(lease))
  let path = execution_cache_child(lease.directory(), lease.digest() + ".json")
  let file = @async_fs.open(path.as_string(), mode=ReadOnly) catch {
    @os_error.OsError(NotFound, ..) => return None
    error => raise execution_cache_error(error)
  }
  defer file.close()
  let size = file.size() catch { error => raise execution_cache_error(error) }
  if size == 0L {
    return None
  }
  let length = Int64::min(size, (@cache.MAX_MANIFEST_BYTES + 1).to_int64()).to_int()
  Some(
    file.at(0L).read_exactly(length) catch {
      error => raise execution_cache_error(error)
    },
  )
}

///|
pub impl @host.HostCacheStore for ExecutionFs with fn write_cache_manifest(
  _self : ExecutionFs,
  lease : @host.CacheLease,
  contents : Bytes,
) -> Unit raise @host.HostError {
  ignore(require_execution_cache_lease(lease))
  if contents.length() > @cache.MAX_MANIFEST_BYTES {
    raise InvalidInput("cache manifest exceeds size limit")
  }
  let destination = execution_cache_child(
    lease.directory(),
    lease.digest() + ".json",
  )
  let temporary = execution_cache_child(
    lease.directory(),
    "." + lease.digest() + ".tmp",
  )
  @async_fs.write_binary(
    temporary.as_string(),
    contents,
    create_mode=CreateNew,
    permission=0o600,
    sync=Full,
  ) catch {
    error => raise execution_cache_error(error)
  }
  @async_fs.rename(temporary.as_string(), destination.as_string(), replace=true) catch {
    error => raise execution_cache_error(error)
  }
}

///|
pub impl @host.HostCacheStore for ExecutionFs with fn release_cache_lease(
  _self : ExecutionFs,
  lease : @host.CacheLease,
) -> Unit raise @host.HostError {
  let lock = require_execution_cache_lease(lease)
  execution_cache_locks.remove(lease.token())
  release_execution_cache_lock(lock) catch {
    error => raise execution_cache_error(error)
  }
}

///|
async fn clean_execution_cache_entry(
  host : ExecutionFs,
  directory : @path.PathValue,
  digest : String,
  recipe_prefix : String?,
) -> Bool raise @host.HostError {
  let lease = @host.HostCacheStore::acquire_cache_lease(host, directory, digest)
  try {
    defer @async.protect_from_cancel(() => {
      try @host.HostCacheStore::release_cache_lease(host, lease) catch {
        _ => ()
      } noraise {
        _ => ()
      }
    })
    if recipe_prefix is Some(prefix) {
      match @host.HostCacheStore::read_cache_manifest(host, lease) {
        Some(bytes) => {
          let text = @utf8.decode(bytes) catch {
            _ => raise @host.InvalidInput("failed to decode cache manifest")
          }
          let manifest = @cache.decode_manifest(text) catch {
            _ => raise @host.InvalidInput("failed to parse cache manifest")
          }
          if manifest.recipe() != prefix &&
            !manifest.recipe().has_prefix(prefix + "::") {
            return false
          }
        }
        None => ()
      }
    }
    let path = execution_cache_child(directory, digest + ".json")
    try @async_fs.remove(path.as_string()) catch {
      @os_error.OsError(NotFound, ..) => false
      error => raise execution_cache_error(error)
    } noraise {
      _ => true
    }
  } catch {
    error => raise execution_cache_error(error)
  }
}

///|
pub impl @host.HostCacheStore for ExecutionFs with fn clean_cache(
  self : ExecutionFs,
  directory : @path.PathValue,
  recipe_prefix : String?,
) -> Int32 raise @host.HostError {
  let root = directory.as_string()
  let names = @async_fs.readdir(root, sort=true) catch {
    @os_error.OsError(NotFound, ..) => return 0
    error => raise execution_cache_error(error)
  }
  let digests : Set[String] = Set([])
  for name in names {
    match name.split(".").collect() {
      [digest, "json"] | ["", digest, "tmp" | "lease"] if cache_hex(
          digest.to_owned(),
          64,
        ) => digests.add(digest.to_owned())
      ["", digest, nonce, "stage"] if recipe_prefix is None &&
        cache_hex(digest.to_owned(), 64) &&
        cache_hex(nonce.to_owned(), 24) => {
        let stage = execution_cache_child(directory, name).as_string()
        try {
          if @async_fs.kind(stage, follow_symlink=false) == Directory {
            @async_fs.remove(stage + "/" + nonce.to_owned(), allow_missing=true)
            remove_empty_directory(stage)
          }
        } catch {
          @os_error.OsError(NotFound, ..) => ()
          error => raise execution_cache_error(error)
        }
      }
      _ => ()
    }
  }
  let mut removed = 0
  for digest in digests {
    if clean_execution_cache_entry(self, directory, digest, recipe_prefix) {
      removed += 1
    }
  }
  // A new publisher may have populated the directory since the scan.
  remove_empty_directory(root) catch {
    error => raise execution_cache_error(error)
  }
  removed
}
