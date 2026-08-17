///|
let native_cache_locks : Map[Int, @async_fs.File] = Map([])

///|
let native_cache_keys : Map[Int, String] = Map([])

///|
let native_cache_token : Ref[Int] = Ref(0)

///|
fn native_cache_error(error : Error) -> @host.HostError {
  match error {
    @os_error.OSError(_) as value if value.is_EACCES() =>
      PermissionDenied(FsWrite, detail="cache filesystem permission denied")
    @os_error.OSError(_) as value if value.is_ENOENT() =>
      InvalidInput("cache path does not exist")
    _ => InvalidInput("cache filesystem operation failed: " + error.to_string())
  }
}

///|
fn native_cache_child(
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
fn native_valid_cache_digest(digest : String) -> Bool {
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
fn native_cache_temporary_name(digest : String) -> String {
  "." + digest + ".tmp"
}

///|
fn native_cache_temporary_digest(name : String) -> String? {
  if name.length() != 69 || !name.has_prefix(".") || !name.has_suffix(".tmp") {
    return None
  }
  let digest = name[1:65].to_owned()
  if native_valid_cache_digest(digest) {
    Some(digest)
  } else {
    None
  }
}

///|
async fn clean_native_cache_temporary(
  directory : @path.PathValue,
  digest : String,
) -> Unit raise @host.HostError {
  let path = native_cache_child(directory, native_cache_temporary_name(digest))
  try @async_fs.remove(path.as_string()) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => ()
    error => raise native_cache_error(error)
  } noraise {
    _ => ()
  }
}

///|
fn next_native_cache_token() -> Int {
  let mut token = native_cache_token.val
  while native_cache_locks.contains(token) {
    token += 1
  }
  native_cache_token.val = token + 1
  token
}

///|
fn native_cache_storage_key(
  directory : @path.PathValue,
  digest : String,
) -> String {
  directory.as_string() + "|" + digest
}

///|
pub impl @host.HostCacheStore for NativeFs with fn acquire_cache_lease(
  _self : NativeFs,
  directory : @path.PathValue,
  digest : String,
) -> @host.CacheLease raise @host.HostError {
  if !native_valid_cache_digest(digest) {
    raise InvalidInput("invalid cache digest")
  }
  @async_fs.mkdir(directory.as_string(), permission=0o700, recursive=true) catch {
    @os_error.OSError(_) as error if error.is_EEXIST() => ()
    error => raise native_cache_error(error)
  }
  let lock_path = native_cache_child(directory, digest + ".json")
  let file = @async_fs.open(
    lock_path.as_string(),
    mode=ReadWrite,
    sync=Full,
    create_mode=OpenOrCreate,
    permission=0o600,
  ) catch {
    error => raise native_cache_error(error)
  }
  try file.lock(Exclusive) catch {
    error => {
      file.close()
      raise native_cache_error(error)
    }
  } noraise {
    _ => ()
  }
  try clean_native_cache_temporary(directory, digest) catch {
    error => {
      file.unlock()
      file.close()
      raise error
    }
  } noraise {
    _ => ()
  }
  let token = next_native_cache_token()
  native_cache_locks[token] = file
  native_cache_keys[token] = native_cache_storage_key(directory, digest)
  @host.CacheLease::new(directory, digest, token)
}

///|
fn require_native_cache_lease(
  lease : @host.CacheLease,
) -> @async_fs.File raise @host.HostError {
  guard native_cache_locks.get(lease.token()) is Some(file) else {
    raise InvalidInput("cache lease is not held")
  }
  if native_cache_keys.get(lease.token()) !=
    Some(native_cache_storage_key(lease.directory(), lease.digest())) {
    raise InvalidInput("cache lease does not match cache key")
  }
  file
}

///|
pub impl @host.HostCacheStore for NativeFs with fn read_cache_manifest(
  _self : NativeFs,
  lease : @host.CacheLease,
) -> Bytes? raise @host.HostError {
  let file = require_native_cache_lease(lease)
  let size = file.size() catch { error => raise native_cache_error(error) }
  if size == 0L {
    return None
  }
  let length = Int64::min(size, (@cache.MAX_MANIFEST_BYTES + 1).to_int64()).to_int()
  let buffer = FixedArray::make(length, b'\x00')
  let count = file.read_at(buffer, position=0) catch {
    error => raise native_cache_error(error)
  }
  Some(buffer.unsafe_reinterpret_as_bytes()[:count].to_owned())
}

///|
pub impl @host.HostCacheStore for NativeFs with fn write_cache_manifest(
  _self : NativeFs,
  lease : @host.CacheLease,
  contents : Bytes,
) -> Unit raise @host.HostError {
  ignore(require_native_cache_lease(lease))
  if contents.length() > @cache.MAX_MANIFEST_BYTES {
    raise InvalidInput("cache manifest exceeds size limit")
  }
  let destination = native_cache_child(
    lease.directory(),
    lease.digest() + ".json",
  )
  @async_fs.write_file(
    destination.as_string(),
    contents,
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  ) catch {
    error => raise native_cache_error(error)
  }
}

///|
pub impl @host.HostCacheStore for NativeFs with fn release_cache_lease(
  _self : NativeFs,
  lease : @host.CacheLease,
) -> Unit raise @host.HostError {
  let file = require_native_cache_lease(lease)
  native_cache_locks.remove(lease.token())
  native_cache_keys.remove(lease.token())
  file.unlock()
  file.close()
}

///|
fn native_cache_manifest_name(name : String) -> String? {
  if name.length() != 69 || !name.has_suffix(".json") {
    return None
  }
  let digest = name[:64].to_owned()
  if native_valid_cache_digest(digest) {
    Some(digest)
  } else {
    None
  }
}

///|
async fn clean_native_cache_entry(
  host : NativeFs,
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
      let path = native_cache_child(directory, name)
      try @async_fs.remove(path.as_string()) catch {
        @os_error.OSError(_) as error if error.is_ENOENT() => false
        error => raise native_cache_error(error)
      } noraise {
        _ => true
      }
    }
  catch {
    error => raise native_cache_error(error)
  }
}

///|
async fn clean_native_stale_temporary(
  host : NativeFs,
  directory : @path.PathValue,
  digest : String,
) -> Unit raise @host.HostError {
  ignore(host)
  clean_native_cache_temporary(directory, digest)
}

///|
pub impl @host.HostCacheStore for NativeFs with fn clean_cache(
  self : NativeFs,
  directory : @path.PathValue,
  recipe_prefix : String?,
) -> Int raise @host.HostError {
  let names = try @async_fs.readdir(directory.as_string(), sort=true) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => return 0
    error => raise native_cache_error(error)
  } noraise {
    value => value
  }
  let mut removed = 0
  for name in names {
    if recipe_prefix is None &&
      native_cache_temporary_digest(name) is Some(digest) {
      clean_native_stale_temporary(self, directory, digest)
      continue
    }
    guard native_cache_manifest_name(name) is Some(digest) else { continue }
    if clean_native_cache_entry(self, directory, name, digest, recipe_prefix) {
      removed += 1
    }
  }
  let remaining = @async_fs.readdir(directory.as_string(), sort=true) catch {
    error => raise native_cache_error(error)
  }
  if remaining.is_empty() {
    try @async_fs.remove(directory.as_string()) catch {
      @os_error.OSError(_) as error if error.is_ENOENT() => ()
      error => raise native_cache_error(error)
    } noraise {
      _ => ()
    }
  }
  removed
}
