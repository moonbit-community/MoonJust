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
    let name = @path.PathValue::new(
      stem + "." + execution_suffix() + extension,
      directory.flavor(),
    ) catch {
      _ => raise InvalidInput("invalid temporary script name")
    }
    let path = directory.join(name) catch {
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
      @os_error.OSError(_) as error if error.is_EEXIST() => continue
      error => raise execution_fs_error(error)
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
  @async_fs.remove(path.as_string()) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => ()
    error => raise execution_fs_error(error)
  }
}
