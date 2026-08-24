///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub struct PortableHost {
  /// Minimal filesystem and environment adapter for the wasm1 runtime.
  ///
  /// The native adapter also carries native-only cache, process, and platform
  /// shims. Keeping the portable host local prevents those implementations from
  /// becoming reachable from the shared wasm executable.
  marker : Unit
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub fn PortableHost::new() -> PortableHost {
  { marker: () }
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
fn portable_io_error(error : @fs.IOError) -> @host.HostError {
  match error {
    IOError(detail) => InvalidInput(detail)
  }
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
fn portable_file_size(path : String) -> Int64 raise @host.HostError {
  let contents = @fs.read_file_to_bytes(path) catch {
    error => raise portable_io_error(error)
  }
  contents.length().to_int64()
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl @host.HostFs for PortableHost with fn read_file(
  _self : PortableHost,
  path : @path.PathValue,
) -> Bytes raise @host.HostError {
  @fs.read_file_to_bytes(path.as_string()) catch {
    error => raise portable_io_error(error)
  }
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl @host.HostFs for PortableHost with fn read_file_range(
  _self : PortableHost,
  path : @path.PathValue,
  offset : Int64,
  length : Int,
) -> Bytes raise @host.HostError {
  if offset < 0L || length < 0 || offset > 0x7fff_ffffL {
    raise InvalidInput("file range must be representable and non-negative")
  }
  let contents = @fs.read_file_to_bytes(path.as_string()) catch {
    error => raise portable_io_error(error)
  }
  let start = offset.to_int()
  if start >= contents.length() {
    return b""
  }
  contents[start:Int::min(contents.length(), start + length)].to_owned()
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl @host.HostFs for PortableHost with fn write_file(
  _self : PortableHost,
  path : @path.PathValue,
  contents : Bytes,
) -> Unit raise @host.HostError {
  @fs.write_bytes_to_file(path.as_string(), contents) catch {
    error => raise portable_io_error(error)
  }
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl @host.HostFs for PortableHost with fn file_exists(
  _self : PortableHost,
  path : @path.PathValue,
) -> Bool raise @host.HostError {
  @fs.path_exists(path.as_string())
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl @host.HostFs for PortableHost with fn read_dir(
  _self : PortableHost,
  path : @path.PathValue,
) -> Array[String] raise @host.HostError {
  if !@fs.path_exists(path.as_string()) {
    raise NotFound(path)
  }
  @fs.read_dir(path.as_string()) catch {
    error => raise portable_io_error(error)
  }
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl @host.HostFs for PortableHost with fn metadata(
  _self : PortableHost,
  path : @path.PathValue,
) -> @host.FileMetadata raise @host.HostError {
  let value = path.as_string()
  let is_file = @fs.is_file(value) catch {
    error => raise portable_io_error(error)
  }
  let is_directory = @fs.is_dir(value) catch {
    error => raise portable_io_error(error)
  }
  if is_file {
    @host.FileMetadata::new_with_executable(
      true,
      false,
      portable_file_size(value),
      true,
    )
  } else if is_directory {
    @host.FileMetadata::new(false, true, 0L)
  } else if @fs.path_exists(value) {
    @host.FileMetadata::new(false, false, 0L)
  } else {
    raise NotFound(path)
  }
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl @host.HostFs for PortableHost with fn canonicalize(
  _self : PortableHost,
  path : @path.PathValue,
) -> @path.PathValue raise @host.HostError {
  path
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl @host.HostFs for PortableHost with fn persist_temp_file(
  _self : PortableHost,
  _temporary : @path.PathValue,
  _destination : @path.PathValue,
  _overwrite : Bool,
) -> Unit raise @host.HostError {
  raise CapabilityUnavailable(FsWrite)
}

///|
#cfg(target="wasm")
async fn portable_read_source(
  path : @path.PathValue,
  max_bytes : Int,
) -> Bytes raise @host.HostError {
  if max_bytes < 0 || max_bytes == 0x7fffffff {
    raise InvalidInput("source byte limit is invalid")
  }
  let file = @async_fs.open(path.as_string(), mode=ReadOnly) catch {
    error => raise InvalidInput("source open failed: " + error.to_string())
  }
  defer file.close()
  let read_limit = max_bytes + 1
  let result = Buffer(size_hint=Int::min(read_limit, 64 * 1024))
  while result.length() < read_limit {
    let chunk = file.read_some(
      max_len=Int::min(read_limit - result.length(), 64 * 1024),
    ) catch {
      error => raise InvalidInput("source read failed: " + error.to_string())
    }
    guard chunk is Some(chunk) else { break }
    if chunk.is_empty() {
      break
    }
    result.write_bytes(chunk)
  }
  result.to_bytes()
}

///|
#coverage.skip
#cfg(any(target="wasm-gc", target="js"))
fn portable_read_source(
  path : @path.PathValue,
  max_bytes : Int,
) -> Bytes raise @host.HostError {
  if max_bytes < 0 || max_bytes == 0x7fffffff {
    raise InvalidInput("source byte limit is invalid")
  }
  let contents = @fs.read_file_to_bytes(path.as_string()) catch {
    error => raise portable_io_error(error)
  }
  contents[:Int::min(contents.length(), max_bytes + 1)].to_owned()
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl @host.HostSourceReader for PortableHost with fn read_source(
  _self : PortableHost,
  path : @path.PathValue,
  max_bytes : Int,
) -> Bytes raise @host.HostError {
  portable_read_source(path, max_bytes)
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
fn portable_os() -> @host.OperatingSystem {
  match @env.get_env_var("MOONJUST_OS") {
    Some("linux") => Linux
    Some("macos") | Some("darwin") => Macos
    Some("windows") => Windows
    Some(value) => Other(value)
    None => Other("wasm")
  }
}

///|
/// Rust's `env::consts::ARCH` uses `aarch64` for Apple arm64 hosts. The
/// launcher receives the host-native spelling from `platform.machine()`, so
/// normalize the aliases before exposing the value through `arch()`.
#cfg(any(target="wasm", target="wasm-gc", target="js"))
fn portable_architecture(raw : String?) -> String {
  match raw {
    Some("arm64") | Some("ARM64") => "aarch64"
    Some("amd64") | Some("AMD64") => "x86_64"
    Some(value) => value
    None => "wasm32"
  }
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
fn portable_flavor(os : @host.OperatingSystem) -> @path.PathFlavor {
  match os {
    Windows => Windows
    _ => Unix
  }
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
fn portable_positive_int(name : String) -> Int? {
  guard @env.get_env_var(name) is Some(value) else { return None }
  let parsed = @string.parse_int(value[:]) catch { _ => return None }
  if parsed > 0 {
    Some(parsed)
  } else {
    None
  }
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl @host.HostEnv for PortableHost with fn env_get(
  _self : PortableHost,
  key : String,
) -> String? raise @host.HostError {
  @env.get_env_var(key)
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl @host.HostEnv for PortableHost with fn env_entries(
  _self : PortableHost,
) -> Array[(String, String)] raise @host.HostError {
  let variables = @env.get_env_vars()
  let keys = variables.keys().collect()
  keys.sort_by(fn(left, right) { left.compare(right) })
  keys.map(fn(key) { (key, variables[key]) })
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl @host.HostEnv for PortableHost with fn current_dir(
  _self : PortableHost,
) -> @path.PathValue raise @host.HostError {
  let os = portable_os()
  @path.PathValue::new(@env.current_dir().unwrap_or("."), portable_flavor(os)) catch {
    _ => raise InvalidInput("current directory has an invalid representation")
  }
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl @host.HostClock for PortableHost with fn now_millis(
  _self : PortableHost,
) -> Int64 raise @host.HostError {
  @async.now()
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl @host.HostRandom for PortableHost with fn random_bytes(
  _self : PortableHost,
  count : Int,
) -> Bytes raise @host.HostError {
  if count < 0 {
    raise InvalidInput("random byte count must not be negative")
  }
  guard @env.rand(count) is Some(bytes) else {
    raise CapabilityUnavailable(Random)
  }
  bytes
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl @host.HostTerminal for PortableHost with fn terminal_info(
  _self : PortableHost,
) -> @host.TerminalInfo raise @host.HostError {
  @host.TerminalInfo::new(false, false, false, false)
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl @host.HostPlatform for PortableHost with fn platform_info(
  _self : PortableHost,
) -> @host.PlatformInfo raise @host.HostError {
  let os = portable_os()
  @host.PlatformInfo::new(
    os,
    portable_architecture(@env.get_env_var("MOONJUST_ARCH")),
    portable_flavor(os),
    portable_runtime=true,
    pid?=portable_positive_int("MOONJUST_PID"),
    num_cpus?=portable_positive_int("MOONJUST_NUM_CPUS"),
    executable?=match @env.get_env_var("MOONJUST_EXECUTABLE") {
      Some(value) => Some(value)
      None => @env.args().get(0)
    },
  )
}
