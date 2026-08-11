///|
let execution_cache_locks : Map[Int, @async_fs.File] = Map([])

///|
let execution_cache_keys : Map[Int, String] = Map([])

///|
let execution_cache_token : Ref[Int] = Ref(0)

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
fn execution_valid_cache_digest(digest : String) -> Bool {
  if digest.length() != 64 {
    return false
  }
  for character in digest {
    if !(character >= '0' && character <= '9') &&
      !(character >= 'a' && character <= 'f') {
      return false
    }
  }
  true
}

///|
fn execution_cache_temporary_digest(name : String) -> String? {
  if name.length() != 69 || !name.has_prefix(".") || !name.has_suffix(".tmp") {
    return None
  }
  let digest = name[1:65].to_owned()
  if execution_valid_cache_digest(digest) {
    Some(digest)
  } else {
    None
  }
}

///|
async fn clean_execution_cache_temporary(
  directory : @path.PathValue,
  digest : String,
) -> Unit raise @host.HostError {
  let path = execution_cache_child(directory, "." + digest + ".tmp")
  try @async_fs.remove(path.as_string()) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => ()
    error => raise execution_cache_error(error)
  } noraise {
    _ => ()
  }
}

///|
fn next_execution_cache_token() -> Int {
  let mut token = execution_cache_token.val
  while execution_cache_locks.contains(token) {
    token += 1
  }
  execution_cache_token.val = token + 1
  token
}

///|
fn execution_cache_storage_key(
  directory : @path.PathValue,
  digest : String,
) -> String {
  directory.as_string() + "|" + digest
}

///|
fn execution_cache_error(error : Error) -> @host.HostError {
  match error {
    @os_error.OSError(_) as value if value.is_EACCES() =>
      PermissionDenied(FsWrite, detail="cache filesystem permission denied")
    @os_error.OSError(_) as value if value.is_ENOENT() =>
      InvalidInput("cache path does not exist")
    _ => InvalidInput("cache filesystem operation failed: " + error.to_string())
  }
}

///|
pub impl @host.HostCacheStore for ExecutionFs with fn acquire_cache_lease(
  _self : ExecutionFs,
  directory : @path.PathValue,
  digest : String,
) -> @host.CacheLease raise @host.HostError {
  if !execution_valid_cache_digest(digest) {
    raise InvalidInput("invalid cache digest")
  }
  @async_fs.mkdir(directory.as_string(), permission=0o700, recursive=true) catch {
    @os_error.OSError(_) as error if error.is_EEXIST() => ()
    error => raise execution_cache_error(error)
  }
  let lock_path = execution_cache_child(directory, digest + ".lock")
  let file = @async_fs.open(
    lock_path.as_string(),
    mode=ReadWrite,
    sync=Full,
    create_mode=OpenOrCreate,
    permission=0o600,
  ) catch {
    error => raise execution_cache_error(error)
  }
  try file.lock(Exclusive) catch {
    error => {
      file.close()
      raise execution_cache_error(error)
    }
  } noraise {
    _ => ()
  }
  try clean_execution_cache_temporary(directory, digest) catch {
    error => {
      file.unlock()
      file.close()
      raise error
    }
  } noraise {
    _ => ()
  }
  let token = next_execution_cache_token()
  execution_cache_locks[token] = file
  execution_cache_keys[token] = execution_cache_storage_key(directory, digest)
  @host.CacheLease::new(directory, digest, token)
}

///|
fn require_execution_cache_lease(
  lease : @host.CacheLease,
) -> @async_fs.File raise @host.HostError {
  guard execution_cache_locks.get(lease.token()) is Some(file) else {
    raise InvalidInput("cache lease is not held")
  }
  if execution_cache_keys.get(lease.token()) !=
    Some(execution_cache_storage_key(lease.directory(), lease.digest())) {
    raise InvalidInput("cache lease does not match cache key")
  }
  file
}

///|
async fn read_execution_cache_manifest_file(
  path : @path.PathValue,
) -> Bytes? raise @host.HostError {
  let file = try @async_fs.open(path.as_string(), mode=ReadOnly) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => return None
    error => raise execution_cache_error(error)
  } noraise {
    value => value
  }
  defer file.close()
  let buffer = FixedArray::make(@cache.MAX_MANIFEST_BYTES + 1, b'\x00')
  let length = file.read_at(buffer, position=0) catch {
    error => raise execution_cache_error(error)
  }
  Some(buffer.unsafe_reinterpret_as_bytes()[:length].to_owned())
}

///|
pub impl @host.HostCacheStore for ExecutionFs with fn read_cache_manifest(
  _self : ExecutionFs,
  lease : @host.CacheLease,
) -> Bytes? raise @host.HostError {
  ignore(require_execution_cache_lease(lease))
  let path = execution_cache_child(lease.directory(), lease.digest() + ".json")
  read_execution_cache_manifest_file(path)
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
  try {
    @async_fs.write_file(
      temporary.as_string(),
      contents,
      create_mode=CreateNew,
      permission=0o600,
      sync=Full,
    )
    @async_fs.rename(
      temporary.as_string(),
      destination.as_string(),
      replace=true,
    )
  } catch {
    error => {
      try @async_fs.remove(temporary.as_string()) catch {
        _ => ()
      } noraise {
        _ => ()
      }
      raise execution_cache_error(error)
    }
  }
}

///|
pub impl @host.HostCacheStore for ExecutionFs with fn release_cache_lease(
  _self : ExecutionFs,
  lease : @host.CacheLease,
) -> Unit raise @host.HostError {
  let file = require_execution_cache_lease(lease)
  execution_cache_locks.remove(lease.token())
  execution_cache_keys.remove(lease.token())
  file.unlock()
  file.close()
}

///|
fn execution_cache_manifest_name(name : String) -> String? {
  if name.length() != 69 || !name.has_suffix(".json") {
    return None
  }
  let digest = name[:64].to_owned()
  if execution_valid_cache_digest(digest) {
    Some(digest)
  } else {
    None
  }
}

///|
async fn clean_execution_cache_entry(
  host : ExecutionFs,
  directory : @path.PathValue,
  name : String,
  digest : String,
  recipe_prefix : String?,
) -> Bool raise @host.HostError {
  let lease = @host.HostCacheStore::acquire_cache_lease(host, directory, digest)
  try
    @async.with_task_group() <| group => {
      group.add_defer(() => {
        try @host.HostCacheStore::release_cache_lease(host, lease) catch {
          _ => ()
        } noraise {
          _ => ()
        }
      })
      if recipe_prefix is Some(prefix) {
        guard @host.HostCacheStore::read_cache_manifest(host, lease)
          is Some(bytes) else {
          return false
        }
        if !bytes.is_empty() {
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
      }
      let path = execution_cache_child(directory, name)
      try @async_fs.remove(path.as_string()) catch {
        @os_error.OSError(_) as error if error.is_ENOENT() => false
        error => raise execution_cache_error(error)
      } noraise {
        _ => true
      }
    }
  catch {
    error => raise execution_cache_error(error)
  }
}

///|
async fn clean_execution_stale_temporary(
  host : ExecutionFs,
  directory : @path.PathValue,
  digest : String,
) -> Unit raise @host.HostError {
  let lease = @host.HostCacheStore::acquire_cache_lease(host, directory, digest)
  @host.HostCacheStore::release_cache_lease(host, lease)
}

///|
pub impl @host.HostCacheStore for ExecutionFs with fn clean_cache(
  self : ExecutionFs,
  directory : @path.PathValue,
  recipe_prefix : String?,
) -> Int raise @host.HostError {
  let names = try @async_fs.readdir(directory.as_string(), sort=true) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => return 0
    error => raise execution_cache_error(error)
  } noraise {
    value => value
  }
  let mut removed = 0
  for name in names {
    if recipe_prefix is None &&
      execution_cache_temporary_digest(name) is Some(digest) {
      clean_execution_stale_temporary(self, directory, digest)
      continue
    }
    guard execution_cache_manifest_name(name) is Some(digest) else { continue }
    if clean_execution_cache_entry(self, directory, name, digest, recipe_prefix) {
      removed += 1
    }
  }
  removed
}
