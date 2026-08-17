///|
/// A policy-aware wasm1 filesystem adapter. Synchronous reads and ordinary
/// writes use the MoonBit host filesystem surface; atomic transactions use the
/// async runtime so moonrun applies the configured create/remove/rename policy.
pub struct PolicyFs {
  inner : @host_native.NativeFs
}

///|
pub fn PolicyFs::new() -> PolicyFs {
  { inner: @host_native.NativeFs::new() }
}

///|
pub impl @host.HostSourceReader for PolicyFs with fn read_source(
  self : PolicyFs,
  path : @path.PathValue,
  max_bytes : Int,
) -> Bytes raise @host.HostError {
  @host.HostSourceReader::read_source(self.inner, path, max_bytes)
}

///|
fn policy_error(error : Error, path : @path.PathValue) -> @host.HostError {
  match error {
    @os_error.OSError(_) as os_error if os_error.is_EEXIST() =>
      AlreadyExists(path)
    @os_error.OSError(_) as os_error if os_error.is_ENOENT() => NotFound(path)
    @os_error.OSError(_) as os_error if os_error.is_EACCES() =>
      PermissionDenied(FsWrite, detail="filesystem permission denied")
    @os_error.OSError(errno, ..) =>
      InvalidInput("filesystem transaction failed with status \{errno}")
    _ => InvalidInput("filesystem transaction failed")
  }
}

///|
fn transaction_suffix() -> String raise @host.HostError {
  guard @env.rand(12) is Some(bytes) else {
    raise CapabilityUnavailable(Random)
  }
  let digits = "0123456789abcdef"
  let builder = StringBuilder()
  for byte in bytes {
    builder.write_char(digits.get_char((byte.to_int() >> 4) & 0xf).unwrap())
    builder.write_char(digits.get_char(byte.to_int() & 0xf).unwrap())
  }
  builder.to_string()
}

///|
async fn remove_after_failure(path : @path.PathValue) -> Unit {
  try
    @async.protect_from_cancel(
      () => @async_fs.remove(path.as_string()),
      resume_on_cancel=false,
    )
  catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
pub impl @host.HostAtomicFs for PolicyFs with fn write_file_atomic(
  _self : PolicyFs,
  path : @path.PathValue,
  contents : Bytes,
  overwrite : Bool,
) -> Unit raise @host.HostError {
  let directory = match path.parent() {
    Some(value) => value
    None =>
      raise InvalidInput("atomic write target must have a parent directory")
  }
  for _ in 0..<128 {
    let name = @path.PathValue::new(
      ".moonjust.tmp." + transaction_suffix(),
      directory.flavor(),
    ) catch {
      _ => raise InvalidInput("invalid temporary file name")
    }
    let temporary = directory.join(name) catch {
      _ => raise InvalidInput("temporary file path flavor mismatch")
    }
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
        try remove_after_failure(temporary) catch {
          _ => ()
        } noraise {
          _ => ()
        }
        raise policy_error(error, temporary)
      }
    } noraise {
      _ => ()
    }
    try
      @async_fs.rename(
        temporary.as_string(),
        path.as_string(),
        replace=overwrite,
      )
    catch {
      error => {
        try remove_after_failure(temporary) catch {
          _ => ()
        } noraise {
          _ => ()
        }
        raise policy_error(error, path)
      }
    } noraise {
      _ => return
    }
  }
  raise InvalidInput("temporary file namespace exhausted")
}

///|
pub impl @host.HostFs for PolicyFs with fn read_file(
  self : PolicyFs,
  path : @path.PathValue,
) -> Bytes raise @host.HostError {
  @host.HostFs::read_file(self.inner, path)
}

///|
pub impl @host.HostFs for PolicyFs with fn read_file_range(
  self : PolicyFs,
  path : @path.PathValue,
  offset : Int64,
  length : Int,
) -> Bytes raise @host.HostError {
  if offset < 0L || length < 0 || offset > 0x7fff_ffffL {
    raise InvalidInput("file range must be representable and non-negative")
  }
  let contents = @host.HostFs::read_file(self.inner, path)
  let start = offset.to_int()
  if start >= contents.length() {
    return b""
  }
  contents[start:Int::min(contents.length(), start + length)].to_owned()
}

///|
pub impl @host.HostFs for PolicyFs with fn write_file(
  self : PolicyFs,
  path : @path.PathValue,
  contents : Bytes,
) -> Unit raise @host.HostError {
  @host.HostFs::write_file(self.inner, path, contents)
}

///|
pub impl @host.HostFs for PolicyFs with fn file_exists(
  self : PolicyFs,
  path : @path.PathValue,
) -> Bool raise @host.HostError {
  @host.HostFs::file_exists(self.inner, path)
}

///|
pub impl @host.HostFs for PolicyFs with fn read_dir(
  self : PolicyFs,
  path : @path.PathValue,
) -> Array[String] raise @host.HostError {
  @host.HostFs::read_dir(self.inner, path)
}

///|
pub impl @host.HostFs for PolicyFs with fn metadata(
  self : PolicyFs,
  path : @path.PathValue,
) -> @host.FileMetadata raise @host.HostError {
  let contents = @host.HostFs::read_file(self.inner, path) catch {
    _ => {
      ignore(@host.HostFs::read_dir(self.inner, path))
      return @host.FileMetadata::new(false, true, 0L)
    }
  }
  @host.FileMetadata::new(true, false, contents.length().to_int64())
}

///|
pub impl @host.HostFs for PolicyFs with fn canonicalize(
  self : PolicyFs,
  path : @path.PathValue,
) -> @path.PathValue raise @host.HostError {
  @host.HostFs::canonicalize(self.inner, path)
}

///|
pub impl @host.HostFs for PolicyFs with fn persist_temp_file(
  _self : PolicyFs,
  _temporary : @path.PathValue,
  _destination : @path.PathValue,
  _overwrite : Bool,
) -> Unit raise @host.HostError {
  raise CapabilityUnavailable(FsWrite)
}
