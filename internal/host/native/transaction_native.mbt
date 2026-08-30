///|
#cfg(platform="windows")
priv struct NativePath(String)

///|
#cfg(not(platform="windows"))
priv struct NativePath(Bytes)

///|
#cfg(platform="windows")
fn NativePath::from_path(path : @path.PathValue) -> NativePath {
  NativePath(path.as_string())
}

///|
#cfg(not(platform="windows"))
fn NativePath::from_path(path : @path.PathValue) -> NativePath {
  NativePath(@utf8.encode(path.as_string()) + Bytes::make(1, (0).to_byte()))
}

///|
fn transaction_status(error : Int) -> Int {
  let value = @os_error.OSError(error, context="filesystem transaction")
  if value.is_EEXIST() {
    1
  } else if value.is_EACCES() {
    2
  } else if value.is_ENOENT() || value.is_ENOTDIR() {
    3
  } else {
    4
  }
}

///|
#cfg(not(platform="windows"))
#borrow(path)
extern "C" fn native_open_exclusive(
  path : Bytes,
  flags : Int,
  mode : Int,
) -> Int = "open"

///|
#cfg(platform="windows")
#borrow(path)
extern "C" fn native_open_exclusive_windows(
  path : String,
  flags : Int,
  share : Int,
  mode : Int,
) -> Int = "_wsopen"

///|
#cfg(not(platform="windows"))
#borrow(buffer)
extern "C" fn native_write(fd : Int, buffer : Bytes, count : Int) -> Int = "write"

///|
#cfg(platform="windows")
#borrow(buffer)
extern "C" fn native_write(fd : Int, buffer : Bytes, count : Int) -> Int = "_write"

///|
#cfg(not(platform="windows"))
#borrow(path)
extern "C" fn native_unlink(path : Bytes) -> Int = "unlink"

///|
#cfg(platform="windows")
#borrow(path)
extern "C" fn native_unlink(path : String) -> Int = "_wremove"

///|
#cfg(not(platform="windows"))
extern "C" fn native_close(fd : Int) -> Int = "close"

///|
#cfg(platform="windows")
extern "C" fn native_close(fd : Int) -> Int = "_close"

///|
#cfg(not(platform="windows"))
extern "C" fn native_sync(fd : Int) -> Int = "fsync"

///|
#cfg(platform="windows")
extern "C" fn native_sync(fd : Int) -> Int = "_commit"

///|
#cfg(not(platform="windows"))
#borrow(old_path, new_path)
extern "C" fn native_rename(old_path : Bytes, new_path : Bytes) -> Int = "rename"

///|
#cfg(not(platform="windows"))
#borrow(old_path, new_path)
extern "C" fn native_link(old_path : Bytes, new_path : Bytes) -> Int = "link"

///|
#cfg(not(platform="windows"))
#borrow(path)
extern "C" fn native_chmod(path : Bytes, mode : Int) -> Int = "chmod"

///|
#cfg(not(platform="windows"))
#borrow(path, metadata)
extern "C" fn native_stat(path : Bytes, metadata : Bytes) -> Int = "stat"

///|
#cfg(platform="windows")
#borrow(path)
extern "C" fn native_chmod(path : String, mode : Int) -> Int = "_wchmod"

///|
#cfg(platform="windows")
#borrow(old_path, new_path)
extern "C" fn native_move_temp(
  old_path : String,
  new_path : String,
  flags : UInt,
) -> Int = "MoveFileExW"

///|
#cfg(platform="windows")
#borrow(path)
extern "C" fn native_file_attributes(path : String) -> UInt = "GetFileAttributesW"

///|
#cfg(platform="windows")
#borrow(path)
extern "C" fn native_set_file_attributes(
  path : String,
  attributes : UInt,
) -> Int = "SetFileAttributesW"

///|
#cfg(platform="windows")
extern "C" fn native_last_error() -> Int = "GetLastError"

///|
#cfg(platform="windows")
fn native_open_exclusive_value(path : NativePath) -> Int {
  match path {
    NativePath(value) => native_open_exclusive_windows(value, 34049, 32, 384)
  }
}

///|
#cfg(not(platform="windows"))
fn native_open_exclusive_value(path : NativePath) -> Int {
  match path {
    NativePath(value) =>
      native_open_exclusive(value, native_exclusive_flags(), 0o600)
  }
}

///|
fn native_exclusive_flags() -> Int {
  if native_operating_system() == 2 {
    2561
  } else {
    193
  }
}

///|
#cfg(platform="windows")
fn native_unlink_value(path : NativePath) -> Int {
  match path {
    NativePath(value) => native_unlink(value)
  }
}

///|
/// Return `(status, mode)` for an existing POSIX destination. The mode field
/// is the only metadata needed to preserve atomic overwrite semantics.
#cfg(not(platform="windows"))
fn native_destination_mode(path : NativePath) -> (Int, Int) {
  match path {
    NativePath(value) => {
      let metadata = Bytes::make(512, 0)
      if native_stat(value, metadata) == 0 {
        // Darwin places st_mode at byte 4; Linux places it at byte 24.
        let offset = if native_operating_system() == 2 { 4 } else { 24 }
        let mode = metadata[offset].to_int() |
          (metadata[offset + 1].to_int() << 8)
        (0, mode & 0o7777)
      } else {
        let error = @os_error.get_errno()
        if @os_error.OSError(error, context="filesystem transaction").is_ENOENT() {
          (3, 0)
        } else {
          (transaction_status(error), 0)
        }
      }
    }
  }
}

///|
#cfg(platform="windows")
fn native_set_temp_mode(_path : NativePath) -> Int {
  0
}

///|
#cfg(not(platform="windows"))
fn native_set_temp_mode(path : NativePath) -> Int {
  match path {
    NativePath(value) => native_chmod(value, 0o600)
  }
}

///|
#cfg(not(platform="windows"))
fn native_unlink_value(path : NativePath) -> Int {
  match path {
    NativePath(value) => native_unlink(value)
  }
}

///|
fn create_exclusive_ffi(path : NativePath, contents : Bytes) -> Int {
  let descriptor = native_open_exclusive_value(path)
  if descriptor < 0 {
    transaction_status(@os_error.get_errno())
  } else {
    let mut offset = 0
    let mut failure = 0
    while offset < contents.length() && failure == 0 {
      let written = native_write(
        descriptor,
        contents[offset:].to_owned(),
        contents.length() - offset,
      )
      if written <= 0 {
        failure = transaction_status(@os_error.get_errno())
      } else {
        offset += written
      }
    }
    if failure == 0 {
      if native_set_temp_mode(path) != 0 {
        failure = transaction_status(@os_error.get_errno())
      }
    }
    if failure == 0 {
      let sync_result = native_sync(descriptor)
      let sync_error = @os_error.get_errno()
      let close_result = native_close(descriptor)
      if sync_result != 0 || close_result != 0 {
        failure = transaction_status(
          if sync_result != 0 {
            sync_error
          } else {
            @os_error.get_errno()
          },
        )
      }
    } else {
      ignore(native_close(descriptor))
    }
    if failure != 0 {
      ignore(native_unlink_value(path))
    }
    failure
  }
}

///|
#cfg(platform="windows")
fn persist_temp_ffi(
  temporary : NativePath,
  destination : NativePath,
  overwrite : Bool,
) -> Int {
  let (temporary, destination) = match (temporary, destination) {
    (NativePath(temporary), NativePath(destination)) => (temporary, destination)
  }
  let attributes = native_file_attributes(destination)
  if attributes != 4294967295U && (attributes & 1U) != 0U {
    2
  } else {
    let flags = 8U | (if overwrite { 1U } else { 0U })
    if native_move_temp(temporary, destination, flags) != 0 {
      0
    } else {
      match native_last_error() {
        80 | 183 => 1
        2 | 3 => 3
        5 | 32 => 2
        _ => 4
      }
    }
  }
}

///|
#cfg(not(platform="windows"))
fn persist_temp_ffi(
  temporary : NativePath,
  destination : NativePath,
  overwrite : Bool,
) -> Int {
  let (temporary, destination) = match (temporary, destination) {
    (NativePath(temporary), NativePath(destination)) => (temporary, destination)
  }
  if overwrite {
    let (mode_status, mode) = native_destination_mode(NativePath(destination))
    if mode_status != 0 && mode_status != 3 {
      mode_status
    } else if mode_status == 0 && (mode & 0o222) == 0 {
      2
    } else if mode_status == 0 && native_chmod(temporary, mode) != 0 {
      transaction_status(@os_error.get_errno())
    } else if native_rename(temporary, destination) == 0 {
      0
    } else {
      transaction_status(@os_error.get_errno())
    }
  } else if native_link(temporary, destination) != 0 {
    transaction_status(@os_error.get_errno())
  } else if native_unlink(temporary) != 0 {
    let error = @os_error.get_errno()
    ignore(native_unlink(destination))
    transaction_status(error)
  } else {
    0
  }
}

///|
fn set_executable_ffi(path : NativePath) -> Int {
  native_set_executable_value(path)
}

///|
#cfg(platform="windows")
fn native_set_executable_value(_path : NativePath) -> Int {
  0
}

///|
#cfg(not(platform="windows"))
fn native_set_executable_value(path : NativePath) -> Int {
  match path {
    NativePath(value) =>
      if native_chmod(value, 0o700) == 0 {
        0
      } else {
        transaction_status(@os_error.get_errno())
      }
  }
}

///|
fn transaction_error(
  status : Int,
  path : @path.PathValue,
  capability : @host.HostCapability,
) -> @host.HostError {
  match status {
    1 => AlreadyExists(path)
    2 => PermissionDenied(capability, detail="filesystem permission denied")
    3 => NotFound(path)
    _ => InvalidInput("filesystem transaction failed with status \{status}")
  }
}

///|
fn random_suffix() -> String raise @host.HostError {
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
fn create_native_temp(
  directory : @path.PathValue,
  prefix : String,
  contents : Bytes,
) -> @path.PathValue raise @host.HostError {
  if prefix == "" || prefix.contains("/") || prefix.contains("\\") {
    raise InvalidInput("temporary file prefix must be a file name prefix")
  }
  for _ in 0..<128 {
    let filename = @path.PathValue::new(
      prefix + random_suffix(),
      directory.flavor(),
    ) catch {
      _ => raise InvalidInput("invalid temporary file name")
    }
    let candidate = directory.join(filename) catch {
      _ => raise InvalidInput("temporary file path flavor mismatch")
    }
    let status = create_exclusive_ffi(
      NativePath::from_path(candidate),
      contents,
    )
    if status == 0 {
      return candidate
    }
    if status != 1 {
      raise transaction_error(status, candidate, FsWrite)
    }
  }
  raise InvalidInput("temporary file namespace exhausted")
}

///|
fn create_native_script_temp(
  directory : @path.PathValue,
  stem : String,
  extension : String,
  contents : Bytes,
) -> @path.PathValue raise @host.HostError {
  if stem == "" ||
    stem.contains("/") ||
    stem.contains("\\") ||
    extension.contains("/") ||
    extension.contains("\\") {
    raise InvalidInput("invalid temporary script name")
  }
  for attempt in 0..<128 {
    let filename = @path.PathValue::new(
      if attempt == 0 {
        stem + extension
      } else {
        stem + "." + random_suffix() + extension
      },
      directory.flavor(),
    ) catch {
      _ => raise InvalidInput("invalid temporary script name")
    }
    let candidate = directory.join(filename) catch {
      _ => raise InvalidInput("temporary script path flavor mismatch")
    }
    let status = create_exclusive_ffi(
      NativePath::from_path(candidate),
      contents,
    )
    if status == 0 {
      return candidate
    }
    if status != 1 {
      raise transaction_error(status, candidate, FsWrite)
    }
  }
  raise InvalidInput("temporary script namespace exhausted")
}

///|
fn set_native_executable(path : @path.PathValue) -> Unit raise @host.HostError {
  let status = set_executable_ffi(NativePath::from_path(path))
  if status != 0 {
    raise transaction_error(status, path, FsWrite)
  }
}

///|
fn persist_native_temp(
  temporary : @path.PathValue,
  destination : @path.PathValue,
  overwrite : Bool,
) -> Unit raise @host.HostError {
  let status = persist_temp_ffi(
    NativePath::from_path(temporary),
    NativePath::from_path(destination),
    overwrite,
  )
  if status != 0 {
    raise transaction_error(status, destination, FsWrite)
  }
}
