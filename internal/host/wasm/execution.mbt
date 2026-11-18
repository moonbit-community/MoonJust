///|
pub impl @host.HostFs for ExecutionFs with fn write_file(
  _self : ExecutionFs,
  _path : @path.PathValue,
  _contents : Bytes,
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
    @os_error.OsError(AccessDenied, ..) =>
      PermissionDenied(FsWrite, detail="filesystem permission denied")
    @os_error.OsError(NotFound, ..) =>
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
    @os_error.OsError(AlreadyExists, ..) => AlreadyExists(path)
    @os_error.OsError(NotFound, ..) => NotFound(path)
    @os_error.OsError(AccessDenied, ..) =>
      PermissionDenied(FsWrite, detail="filesystem permission denied")
    @os_error.OsError(_, raw_code=errno, ..) =>
      InvalidInput("filesystem transaction failed with status \{errno}")
    _ => InvalidInput("filesystem transaction failed")
  }
}

///|
async fn execution_remove_after_failure(path : @path.PathValue) -> Unit {
  try
    @async.protect_from_cancel(() => @async_fs.remove(path.as_string()))
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
  if overwrite {
    raise InvalidInput(
      "cannot atomically replace an existing file and preserve its permissions",
    )
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
      @async_fs.write_binary(
        temporary.as_string(),
        contents,
        create_mode=CreateNew,
        permission=0o600,
        sync=Full,
      )
    catch {
      @os_error.OsError(AlreadyExists, ..) => continue
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
pub impl @host.HostScriptTemp for ExecutionFs with fn create_script_temp(
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
      @os_error.OsError(AlreadyExists, ..) => continue
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
      @async_fs.write_binary(
        path.as_string(),
        contents,
        create_mode=CreateNew,
        permission=if executable { 0o700 } else { 0o600 },
        sync=Full,
      )
    catch {
      error => {
        try @async_fs.remove(temporary_directory.as_string()) catch {
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
pub impl @host.HostScriptTemp for ExecutionFs with fn remove_script_temp(
  _self : ExecutionFs,
  path : @path.PathValue,
) -> Unit raise @host.HostError {
  let parent = path.parent()
  @async_fs.remove(path.as_string()) catch {
    @os_error.OsError(NotFound, ..) => ()
    error => raise execution_fs_error(error)
  }
  match parent {
    Some(directory) =>
      @async_fs.remove(directory.as_string()) catch {
        @os_error.OsError(NotFound, ..) => ()
        error => raise execution_fs_error(error)
      }
    None => ()
  }
}
