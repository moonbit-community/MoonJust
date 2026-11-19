///|
/// The lock lives in .<digest>.lease/<generation>. Publish a populated
/// directory atomically so contenders see exactly one generation. A waiter
/// that opened an old inode must verify its generation after obtaining the
/// OS lock. Clean and ordinary release may then retire the directory without
/// leaving a permanent entry in the project's tree.
priv struct ExecutionCacheLock {
  file : @async_fs.File
  generation : String
  directory : @path.PathValue
  digest : String
}

///|
fn cache_hex(name : String, length : Int32) -> Bool {
  name.length() == length &&
  name.iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
}

///|
fn lease_directory(
  directory : @path.PathValue,
  digest : String,
) -> String raise @host.HostError {
  execution_cache_child(directory, "." + digest + ".lease").as_string()
}

///|
async fn remove_empty_directory(path : String) -> Unit nocancel {
  try @async_fs.remove(path, allow_missing=true) catch {
    @os_error.OsError(NotEmpty, ..) => ()
    error => raise error
  } noraise {
    _ => ()
  }
}

///|
/// Only the known generation file is removed, even if a foreign file was
/// placed in the staging directory. Clean may reap an interrupted publisher.
/// A publisher that loses its staging path retries discovery from the start.
async fn publish_cache_generation(
  root : String,
  digest : String,
  published : String,
) -> Unit {
  let nonce = execution_suffix()
  let stage = root + "/." + digest + "." + nonce + ".stage"
  // On Darwin, mkdir underneath a directory being removed may report
  // EINVAL as well as ENOENT. Re-resolve the fresh staging path. Preserve
  // persistent errors, including EINVAL from an unsuitable filesystem.
  for attempt in 0..<3 {
    try @async_fs.mkdir(stage, permission=0o700) catch {
      @os_error.OsError(_, raw_code=22, ..) if @async.platform is MacOS &&
        attempt < 2 => continue
      error => raise error
    } noraise {
      _ => break
    }
  }
  let gate = stage + "/" + nonce
  defer {
    @async_fs.remove(gate, allow_missing=true) catch {
      _ => ()
    }
    remove_empty_directory(stage) catch {
      _ => ()
    }
  }
  @async_fs.write_binary(gate, b"", create_mode=CreateNew, permission=0o600)
  try @async_fs.rename(stage, published, replace=false) catch {
    @os_error.OsError(AlreadyExists | NotEmpty, ..) => ()
    error => raise error
  } noraise {
    _ => ()
  }
}

///|
async fn open_execution_cache_lock(
  directory : @path.PathValue,
  digest : String,
) -> ExecutionCacheLock {
  let root = directory.as_string()
  let published = lease_directory(directory, digest)
  for ;; {
    // A concurrent last-entry clean may remove the empty cache directory
    // between mkdir and publication. Only missing names are retryable.
    @async_fs.mkdir(root, permission=0o700, allow_existing=true) catch {
      @os_error.OsError(AlreadyExists, ..) as error => {
        // mkdir saw an existing entry but its directory check lost to clean.
        let kind = @async_fs.kind(root, follow_symlink=false) catch {
          @os_error.OsError(NotFound, ..) => continue
          other => raise other
        }
        guard kind == Directory else { raise error }
      }
      error => raise error
    }
    try {
      let kind = @async_fs.kind(published, follow_symlink=false) catch {
        @os_error.OsError(NotFound, ..) => {
          publish_cache_generation(root, digest, published)
          continue
        }
        error => raise error
      }
      guard kind == Directory else {
        raise @host.InvalidInput("invalid cache lease directory")
      }
      let entries = @async_fs.readdir(published)
      if entries.is_empty() {
        remove_empty_directory(published)
        continue
      }
      guard entries is [generation] && cache_hex(generation, 24) else {
        raise @host.InvalidInput("invalid cache lease generation")
      }
      let path = published + "/" + generation
      guard @async_fs.kind(path, follow_symlink=false) == Regular else {
        raise @host.InvalidInput("invalid cache lease file")
      }
      let file = @async_fs.open(path, mode=ReadWrite)
      let mut owned = false
      defer (if !owned { file.close() })
      file.lock(Exclusive)
      if @async_fs.exists(path) {
        owned = true
        return { file, generation, directory, digest, }
      }
      file.unlock()
    } catch {
      @os_error.OsError(NotFound, ..) => continue
      error => raise error
    }
  }
}

///|
async fn release_execution_cache_lock(lock : ExecutionCacheLock) -> Unit {
  defer {
    lock.file.unlock()
    lock.file.close()
  }
  let published = lease_directory(lock.directory, lock.digest)
  @async_fs.remove(published + "/" + lock.generation)
  remove_empty_directory(published)
}
