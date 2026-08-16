///|
/// Wasm execution filesystem: ordinary project access remains read-only while
/// runtime-owned temporary scripts use policy-checked async filesystem calls.
pub struct ExecutionFs {
  reads : ReadOnlyFs
}

///|
pub fn ExecutionFs::new() -> ExecutionFs {
  { reads: ReadOnlyFs::new() }
}

///|
pub impl @host.HostFs for ExecutionFs with fn read_file(
  self : ExecutionFs,
  path : @path.PathValue,
) -> Bytes raise @host.HostError {
  @host.HostFs::read_file(self.reads, path)
}

///|
pub impl @host.HostFs for ExecutionFs with fn read_file_range(
  self : ExecutionFs,
  path : @path.PathValue,
  offset : Int64,
  length : Int,
) -> Bytes raise @host.HostError {
  @host.HostFs::read_file_range(self.reads, path, offset, length)
}

///|
pub impl @host.HostFs for ExecutionFs with fn write_file(
  _self : ExecutionFs,
  _path : @path.PathValue,
  _contents : Bytes,
) -> Unit raise @host.HostError {
  raise CapabilityDenied(FsWrite)
}

///|
pub impl @host.HostFs for ExecutionFs with fn file_exists(
  self : ExecutionFs,
  path : @path.PathValue,
) -> Bool raise @host.HostError {
  @host.HostFs::file_exists(self.reads, path)
}

///|
pub impl @host.HostFs for ExecutionFs with fn read_dir(
  self : ExecutionFs,
  path : @path.PathValue,
) -> Array[String] raise @host.HostError {
  @host.HostFs::read_dir(self.reads, path)
}

///|
pub impl @host.HostFs for ExecutionFs with fn metadata(
  self : ExecutionFs,
  path : @path.PathValue,
) -> @host.FileMetadata raise @host.HostError {
  @host.HostFs::metadata(self.reads, path)
}

///|
pub impl @host.HostFs for ExecutionFs with fn canonicalize(
  self : ExecutionFs,
  path : @path.PathValue,
) -> @path.PathValue raise @host.HostError {
  @host.HostFs::canonicalize(self.reads, path)
}

///|
pub impl @host.HostFs for ExecutionFs with fn persist_temp_file(
  _self : ExecutionFs,
  _temporary : @path.PathValue,
  _destination : @path.PathValue,
  _overwrite : Bool,
) -> Unit raise @host.HostError {
  raise CapabilityDenied(FsWrite)
}

///|
pub impl @host.HostTemp for ExecutionFs with fn create_temp_file(
  _self : ExecutionFs,
  _directory : @path.PathValue,
  _prefix : String,
  _contents : Bytes,
) -> @path.PathValue raise @host.HostError {
  raise CapabilityDenied(FsWrite)
}

///|
pub impl @host.HostTemp for ExecutionFs with fn remove_temp_file(
  _self : ExecutionFs,
  _path : @path.PathValue,
) -> Unit raise @host.HostError {
  raise CapabilityDenied(FsWrite)
}

///|
fn execution_suffix() -> String raise @host.HostError {
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
fn execution_fs_error(error : Error) -> @host.HostError {
  match error {
    @os_error.OSError(_) as os_error if os_error.is_EACCES() =>
      PermissionDenied(FsWrite, detail="filesystem permission denied")
    @os_error.OSError(_) as os_error if os_error.is_ENOENT() =>
      InvalidInput("temporary script directory does not exist")
    _ => InvalidInput("temporary script filesystem operation failed")
  }
}

///|
fn execution_atomic_error(
  error : Error,
  path : @path.PathValue,
) -> @host.HostError {
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
async fn execution_remove_after_failure(path : @path.PathValue) -> Unit {
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
pub impl @host.HostAtomicFs for ExecutionFs with fn write_file_atomic(
  _self : ExecutionFs,
  path : @path.PathValue,
  contents : Bytes,
  overwrite : Bool,
) -> Unit raise @host.HostError {
  if overwrite && @host.HostFs::file_exists(_self.reads, path) {
    let target = try @async_fs.open(path.as_string(), mode=WriteOnly) catch {
      error => raise execution_atomic_error(error, path)
    } noraise {
      file => file
    }
    target.close()
  }
  let directory = match path.parent() {
    Some(value) => value
    None =>
      raise InvalidInput("atomic write target must have a parent directory")
  }
  for _ in 0..<128 {
    let name = @path.PathValue::new(
      ".moonjust.tmp." + execution_suffix(),
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
        try execution_remove_after_failure(temporary) catch {
          _ => ()
        } noraise {
          _ => ()
        }
        raise execution_atomic_error(error, temporary)
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
        try execution_remove_after_failure(temporary) catch {
          _ => ()
        } noraise {
          _ => ()
        }
        raise execution_atomic_error(error, path)
      }
    } noraise {
      _ => return
    }
  }
  raise InvalidInput("temporary file namespace exhausted")
}

///|
pub impl @host.HostAsyncScriptTemp for ExecutionFs with fn create_script_temp_async(
  _self : ExecutionFs,
  directory : @path.PathValue,
  stem : String,
  extension : String,
  contents : Bytes,
  executable : Bool,
) -> @path.PathValue raise @host.HostError {
  if stem == "" ||
    stem.contains("/") ||
    stem.contains("\\") ||
    extension.contains("/") ||
    extension.contains("\\") {
    raise InvalidInput("invalid temporary script name")
  }
  for _ in 0..<128 {
    let directory_name = @path.PathValue::new(
      "just" + execution_suffix(),
      directory.flavor(),
    ) catch {
      _ => raise InvalidInput("invalid temporary script directory")
    }
    let temporary_directory = directory.join(directory_name) catch {
      _ => raise InvalidInput("temporary script directory flavor mismatch")
    }
    try
      @async_fs.mkdir(
        temporary_directory.as_string(),
        permission=0o700,
        recursive=false,
      )
    catch {
      @os_error.OSError(_) as error if error.is_EEXIST() => continue
      error => raise execution_fs_error(error)
    } noraise {
      _ => ()
    }
    let name = @path.PathValue::new(stem + extension, directory.flavor()) catch {
      _ => raise InvalidInput("invalid temporary script name")
    }
    let path = temporary_directory.join(name) catch {
      _ => raise InvalidInput("temporary script path flavor mismatch")
    }
    try
      @async_fs.write_file(
        path.as_string(),
        contents,
        create_mode=CreateNew,
        permission=if executable { 0o700 } else { 0o600 },
        sync=Full,
      )
    catch {
      error => {
        try @async_fs.rmdir(temporary_directory.as_string()) catch {
          _ => ()
        } noraise {
          _ => ()
        }
        raise execution_fs_error(error)
      }
    } noraise {
      _ => return path
    }
  }
  raise InvalidInput("temporary script namespace exhausted")
}

///|
pub impl @host.HostAsyncScriptTemp for ExecutionFs with fn remove_script_temp_async(
  _self : ExecutionFs,
  path : @path.PathValue,
) -> Unit raise @host.HostError {
  let parent = path.parent()
  @async_fs.remove(path.as_string()) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => ()
    error => raise execution_fs_error(error)
  }
  match parent {
    Some(directory) =>
      @async_fs.rmdir(directory.as_string()) catch {
        @os_error.OSError(_) as error if error.is_ENOENT() => ()
        error => raise execution_fs_error(error)
      }
    None => ()
  }
}
