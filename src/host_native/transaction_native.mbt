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
  NativePath(@utf8.encode(path.as_string()))
}

///|
#borrow(path, contents)
extern "C" fn create_exclusive_ffi(path : NativePath, contents : Bytes) -> Int = "moonjust_host_create_exclusive"

///|
#borrow(temporary, destination)
extern "C" fn persist_temp_ffi(
  temporary : NativePath,
  destination : NativePath,
  overwrite : Bool,
) -> Int = "moonjust_host_persist_temp"

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
