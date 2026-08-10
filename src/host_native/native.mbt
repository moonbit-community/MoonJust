///|
/// Native/wasm filesystem adapter backed by the approved `moonbitlang/x/fs`
/// package. Core packages depend only on `@host.HostFs` and never on this leaf.
pub struct NativeFs {
  marker : Unit
}

///|
pub fn NativeFs::new() -> NativeFs {
  { marker: () }
}

///|
fn io_error(error : @fs.IOError) -> @host.HostError {
  match error {
    IOError(detail) => InvalidInput(detail)
  }
}

///|
pub impl @host.HostFs for NativeFs with fn read_file(
  _self : NativeFs,
  path : @path.PathValue,
) -> Bytes raise @host.HostError {
  @fs.read_file_to_bytes(path.as_string()) catch {
    error => raise io_error(error)
  }
}

///|
pub impl @host.HostFs for NativeFs with fn read_file_range(
  _self : NativeFs,
  path : @path.PathValue,
  offset : Int64,
  length : Int,
) -> Bytes raise @host.HostError {
  if offset < 0L || length < 0 {
    raise InvalidInput("file range must not be negative")
  }
  match read_file_range_value(path.as_string(), offset, length) {
    Some(bytes) => bytes
    None => raise CapabilityUnavailable(FsRead)
  }
}

///|
pub impl @host.HostFs for NativeFs with fn write_file(
  _self : NativeFs,
  path : @path.PathValue,
  contents : Bytes,
) -> Unit raise @host.HostError {
  @fs.write_bytes_to_file(path.as_string(), contents) catch {
    error => raise io_error(error)
  }
}

///|
pub impl @host.HostFs for NativeFs with fn file_exists(
  _self : NativeFs,
  path : @path.PathValue,
) -> Bool raise @host.HostError {
  @fs.path_exists(path.as_string())
}

///|
pub impl @host.HostFs for NativeFs with fn read_dir(
  _self : NativeFs,
  path : @path.PathValue,
) -> Array[String] raise @host.HostError {
  @fs.read_dir(path.as_string()) catch {
    error => raise io_error(error)
  }
}

///|
pub impl @host.HostFs for NativeFs with fn metadata(
  _self : NativeFs,
  path : @path.PathValue,
) -> @host.FileMetadata raise @host.HostError {
  let value = path.as_string()
  let is_file = @fs.is_file(value) catch { error => raise io_error(error) }
  let is_directory = @fs.is_dir(value) catch { error => raise io_error(error) }
  if is_file {
    let size = match file_size_value(value) {
      Some(size) => size
      None => raise CapabilityUnavailable(FsRead)
    }
    @host.FileMetadata::new(true, false, size)
  } else if is_directory {
    @host.FileMetadata::new(false, true, 0L)
  } else {
    raise NotFound(path)
  }
}

///|
pub impl @host.HostFs for NativeFs with fn canonicalize(
  _self : NativeFs,
  path : @path.PathValue,
) -> @path.PathValue raise @host.HostError {
  match canonical_path_string(path.as_string()) {
    None => raise NotFound(path)
    Some(value) =>
      @path.PathValue::new(value, path.flavor()) catch {
        _ => raise InvalidInput("canonical path has an invalid representation")
      }
  }
}

///|
pub impl @host.HostFs for NativeFs with fn persist_temp_file(
  _self : NativeFs,
  temporary : @path.PathValue,
  destination : @path.PathValue,
  overwrite : Bool,
) -> Unit raise @host.HostError {
  persist_native_temp(temporary, destination, overwrite)
}

///|
pub impl @host.HostTemp for NativeFs with fn create_temp_file(
  _self : NativeFs,
  directory : @path.PathValue,
  prefix : String,
  contents : Bytes,
) -> @path.PathValue raise @host.HostError {
  create_native_temp(directory, prefix, contents)
}

///|
pub impl @host.HostTemp for NativeFs with fn remove_temp_file(
  _self : NativeFs,
  path : @path.PathValue,
) -> Unit raise @host.HostError {
  @fs.remove_file(path.as_string()) catch {
    error => raise io_error(error)
  }
}

///|
pub impl @host.HostScriptTemp for NativeFs with fn create_script_temp(
  _self : NativeFs,
  directory : @path.PathValue,
  stem : String,
  extension : String,
  contents : Bytes,
) -> @path.PathValue raise @host.HostError {
  create_native_script_temp(directory, stem, extension, contents)
}

///|
pub impl @host.HostScriptTemp for NativeFs with fn remove_script_temp(
  self : NativeFs,
  path : @path.PathValue,
) -> Unit raise @host.HostError {
  @host.HostTemp::remove_temp_file(self, path)
}

///|
pub impl @host.HostExecutable for NativeFs with fn set_executable(
  _self : NativeFs,
  path : @path.PathValue,
) -> Unit raise @host.HostError {
  set_native_executable(path)
}

///|
pub impl @host.HostAtomicFs for NativeFs with fn write_file_atomic(
  self : NativeFs,
  path : @path.PathValue,
  contents : Bytes,
  overwrite : Bool,
) -> Unit raise @host.HostError {
  @host.write_file_atomic(self, path, contents, overwrite~)
}

///|
pub impl @host.HostEnv for NativeFs with fn env_get(
  _self : NativeFs,
  key : String,
) -> String? raise @host.HostError {
  @env.get_env_var(key)
}

///|
pub impl @host.HostEnv for NativeFs with fn env_entries(_self : NativeFs) -> Array[
  (String, String),
] raise @host.HostError {
  let variables = @env.get_env_vars()
  let keys = variables.keys().collect()
  keys.sort_by(fn(left, right) {
    let length = Int::min(left.length(), right.length())
    for index in 0..<length {
      let order = left.unsafe_get(index).compare(right.unsafe_get(index))
      if order != 0 {
        return order
      }
    }
    left.length().compare(right.length())
  })
  keys.map(fn(key) { (key, variables[key]) })
}

///|
#cfg(platform="windows")
fn native_path_flavor() -> @path.PathFlavor {
  Windows
}

///|
#cfg(not(platform="windows"))
fn native_path_flavor() -> @path.PathFlavor {
  Unix
}

///|
pub impl @host.HostEnv for NativeFs with fn current_dir(_self : NativeFs) -> @path.PathValue raise @host.HostError {
  guard @env.current_dir() is Some(value) else {
    raise CapabilityUnavailable(Environment)
  }
  @path.PathValue::new(value, native_path_flavor()) catch {
    _ => raise InvalidInput("current directory has an invalid representation")
  }
}

///|
pub impl @host.HostRandom for NativeFs with fn random_bytes(
  _self : NativeFs,
  _count : Int,
) -> Bytes raise @host.HostError {
  raise CapabilityUnavailable(Random)
}

///|
pub impl @host.HostTerminal for NativeFs with fn terminal_info(_self : NativeFs) -> @host.TerminalInfo raise @host.HostError {
  @host.TerminalInfo::new(false, false, false, false)
}

///|
pub impl @host.HostPlatform for NativeFs with fn platform_info(_self : NativeFs) -> @host.PlatformInfo raise @host.HostError {
  let flavor = native_path_flavor()
  @host.PlatformInfo::new(
    if flavor == Windows {
      Windows
    } else {
      Other("unix")
    },
    "unknown",
    flavor,
  )
}
