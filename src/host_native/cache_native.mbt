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
  let lock_path = native_cache_child(directory, digest + ".lock")
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
async fn read_native_cache_manifest_file(
  path : @path.PathValue,
) -> Bytes? raise @host.HostError {
  let file = try @async_fs.open(path.as_string(), mode=ReadOnly) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => return None
    error => raise native_cache_error(error)
  } noraise {
    value => value
  }
  defer file.close()
  let buffer = FixedArray::make(@cache.MAX_MANIFEST_BYTES + 1, b'\x00')
  let length = file.read_at(buffer, position=0) catch {
    error => raise native_cache_error(error)
  }
  Some(buffer.unsafe_reinterpret_as_bytes()[:length].to_owned())
}

///|
pub impl @host.HostCacheStore for NativeFs with fn read_cache_manifest(
  _self : NativeFs,
  lease : @host.CacheLease,
) -> Bytes? raise @host.HostError {
  ignore(require_native_cache_lease(lease))
  let path = native_cache_child(lease.directory(), lease.digest() + ".json")
  read_native_cache_manifest_file(path)
}

///|
fn native_cache_temporary_name(
  lease : @host.CacheLease,
  attempt : Int,
) -> String {
  let suffix = match @env.rand(12) {
    Some(bytes) => {
      let digits = "0123456789abcdef"
      let builder = StringBuilder()
      for byte in bytes {
        builder.write_char(digits.get_char((byte.to_int() >> 4) & 0xf).unwrap())
        builder.write_char(digits.get_char(byte.to_int() & 0xf).unwrap())
      }
      builder.to_string()
    }
    None => lease.token().to_string() + "-" + attempt.to_string()
  }
  "." + lease.digest() + "." + suffix + ".tmp"
}

///|
async fn write_native_cache_temporary(
  lease : @host.CacheLease,
  contents : Bytes,
) -> @path.PathValue raise @host.HostError {
  for attempt in 0..<128 {
    let temporary = native_cache_child(
      lease.directory(),
      native_cache_temporary_name(lease, attempt),
    )
    try
      @async_fs.write_file(
        temporary.as_string(),
        contents,
        create_mode=CreateNew,
        permission=0o600,
        sync=Full,
      )
    catch {
      @os_error.OSError(_) as error if error.is_EEXIST() => continue
      error => {
        try @async_fs.remove(temporary.as_string()) catch {
          _ => ()
        } noraise {
          _ => ()
        }
        raise native_cache_error(error)
      }
    } noraise {
      _ => return temporary
    }
  }
  raise InvalidInput("cache temporary filename space exhausted")
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
  let temporary = write_native_cache_temporary(lease, contents)
  @async_fs.rename(temporary.as_string(), destination.as_string(), replace=true) catch {
    error => {
      try @async_fs.remove(temporary.as_string()) catch {
        _ => ()
      } noraise {
        _ => ()
      }
      raise native_cache_error(error)
    }
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
    guard native_cache_manifest_name(name) is Some(digest) else { continue }
    if clean_native_cache_entry(self, directory, name, digest, recipe_prefix) {
      removed += 1
    }
  }
  removed
}
