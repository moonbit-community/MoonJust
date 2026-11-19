///|
pub struct ExecutionFs {
  marker : Unit
}

///|
/// These snapshots are shared by value-copied host adapters during one CLI
/// invocation. `ExecutionFs::new` resets them before a new invocation, while
/// clock and random capabilities remain uncached.
let portable_environment_cache : Ref[Array[(String, String)]?] = Ref(None)

///|
let portable_current_dir_cache : Ref[@path.PathValue?] = Ref(None)

///|
let portable_platform_cache : Ref[@host.PlatformInfo?] = Ref(None)

///|
let portable_terminal_cache : Ref[@host.TerminalInfo?] = Ref(None)

///|
pub fn ExecutionFs::new() -> ExecutionFs {
  portable_environment_cache.val = None
  portable_current_dir_cache.val = None
  portable_platform_cache.val = None
  portable_terminal_cache.val = None
  unix_zone_cache.val = None
  { marker: (), }
}

///|
pub impl @host.HostFs for ExecutionFs with fn read_file(
  _self : ExecutionFs,
  path : @path.PathValue,
) -> Bytes raise @host.HostError {
  @async_fs.read_binary(path.as_string()) catch {
    error => raise read_error(error, path)
  }
}

///|
pub impl @host.HostFs for ExecutionFs with fn read_file_range(
  _self : ExecutionFs,
  path : @path.PathValue,
  offset : Int64,
  length : Int32,
) -> Bytes raise @host.HostError {
  if offset < 0L || length < 0 {
    raise InvalidInput("file range must be non-negative")
  }
  try {
    let file = @async_fs.open(path.as_string(), mode=ReadOnly)
    defer file.close()
    if length == 0 {
      return b""
    }
    let buffer = FixedArray::make(length, b'\x00')
    let count = file.at(offset).read_into(buffer)
    buffer.unsafe_reinterpret_as_bytes()[:count].to_owned()
  } catch {
    error => raise read_error(error, path)
  }
}

///|
pub impl @host.HostFs for ExecutionFs with fn file_exists(
  _self : ExecutionFs,
  path : @path.PathValue,
) -> Bool raise @host.HostError {
  @async_fs.exists(path.as_string()) catch {
    error => raise read_error(error, path)
  }
}

///|
pub impl @host.HostFs for ExecutionFs with fn read_dir(
  _self : ExecutionFs,
  path : @path.PathValue,
) -> Array[String] raise @host.HostError {
  @async_fs.readdir(path.as_string()) catch {
    error => raise read_error(error, path)
  }
}

///|
pub impl @host.HostFs for ExecutionFs with fn metadata(
  _self : ExecutionFs,
  path : @path.PathValue,
) -> @host.FileMetadata raise @host.HostError {
  let kind = @async_fs.kind(path.as_string(), follow_symlink=true) catch {
    error => raise read_error(error, path)
  }
  @host.FileMetadata::new(kind == Regular, kind == Directory)
}

///|
pub impl @host.HostFs for ExecutionFs with fn canonicalize(
  _self : ExecutionFs,
  path : @path.PathValue,
) -> @path.PathValue raise @host.HostError {
  let name = @async_fs.realpath(path.as_string()) catch {
    error => raise read_error(error, path)
  }
  @path.PathValue::new(name, path.flavor()) catch {
    _ => raise InvalidInput("invalid canonical path")
  }
}

///|
async fn portable_read_source(
  path : @path.PathValue,
  max_bytes : Int32,
) -> Bytes raise @host.HostError {
  if max_bytes < 0 || max_bytes == 0x7fffffff {
    raise InvalidInput("source byte limit is invalid")
  }
  let file = @async_fs.open(path.as_string(), mode=ReadOnly) catch {
    error => raise InvalidInput("source open failed: " + error.to_string())
  }
  defer file.close()
  let read_limit = max_bytes + 1
  // Regular files can provide an exact allocation hint without changing the
  // bounded stream semantics used for FIFOs and other special files.
  let regular_file = file.kind() == Regular
  let probed_size = if regular_file {
    file.size() catch {
      _ => 0L
    }
  } else {
    0L
  }
  let size_hint = if probed_size > 0L && probed_size < read_limit.to_int64() {
    probed_size.to_int()
  } else {
    Int32::min(read_limit, 64 * 1024)
  }
  let result = Buffer(capacity=size_hint)
  let buffer = FixedArray::make(Int32::min(read_limit, 64 * 1024), b'\x00')
  while result.length() < read_limit {
    let count = file.read_into(
      buffer,
      max_len=Int32::min(buffer.length(), read_limit - result.length()),
    ) catch {
      error =>
        raise InvalidInput("source read failed: " + (error : Error).to_string())
    }
    if count == 0 {
      break
    }
    result.write_bytes(buffer.unsafe_reinterpret_as_bytes()[:count])
  }
  result.to_bytes()
}

///|
pub impl @host.HostFs for ExecutionFs with fn read_source(
  _self : ExecutionFs,
  path : @path.PathValue,
  max_bytes : Int32,
) -> Bytes raise @host.HostError {
  portable_read_source(path, max_bytes)
}

///|
fn portable_os() -> @host.OperatingSystem {
  match @async.platform {
    Linux => Linux
    MacOS => Macos
    Windows => Windows
    @types.Platform::.. => Other("unknown")
  }
}

///|
/// Rust's `env::consts::ARCH` uses `aarch64` for Apple arm64 hosts. The
/// launcher receives the host-native spelling from `platform.machine()`, so
/// normalize the aliases before exposing the value through `arch()`.
fn portable_architecture(raw : String?) -> String? {
  match raw {
    Some("arm64") | Some("ARM64") => Some("aarch64")
    Some("amd64") | Some("AMD64") => Some("x86_64")
    value => value
  }
}

///|
fn portable_flavor(os : @host.OperatingSystem) -> @path.PathFlavor {
  match os {
    Windows => Windows
    _ => Unix
  }
}

///|
fn portable_positive_int(name : String) -> Int32? {
  guard @env.get_env_var(name) is Some(value) else { return None }
  let parsed = @string.parse_int(value[:]) catch { _ => return None }
  if parsed > 0 {
    Some(parsed)
  } else {
    None
  }
}

///|
pub impl @host.HostEnv for ExecutionFs with fn env_get(
  _self : ExecutionFs,
  key : String,
) -> String? raise @host.HostError {
  for entry in portable_environment() {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None
}

///|
pub impl @host.HostEnv for ExecutionFs with fn env_entries(_self : ExecutionFs) -> Array[
  (String, String),
] raise @host.HostError {
  portable_environment().copy()
}

///|
fn portable_environment() -> Array[(String, String)] {
  match portable_environment_cache.val {
    Some(value) => value
    None => {
      let variables = @env.get_env_vars()
      let keys = variables.keys().collect()
      keys.sort_by(fn(left, right) { left.compare(right) })
      let value = keys.map(fn(key) { (key, variables[key]) })
      portable_environment_cache.val = Some(value)
      value
    }
  }
}

///|
fn portable_current_dir() -> @path.PathValue raise @host.HostError {
  match portable_current_dir_cache.val {
    Some(value) => value
    None => {
      let os = portable_os()
      let value = @path.PathValue::new(
        @env.current_dir().unwrap_or("."),
        portable_flavor(os),
      ) catch {
        _ =>
          raise InvalidInput("current directory has an invalid representation")
      }
      portable_current_dir_cache.val = Some(value)
      value
    }
  }
}

///|
fn portable_platform() -> @host.PlatformInfo {
  match portable_platform_cache.val {
    Some(value) => value
    None => {
      let os = portable_os()
      let value = @host.PlatformInfo::new(
        os,
        portable_architecture(@env.get_env_var("MOONJUST_ARCH")),
        portable_flavor(os),
        pid?=portable_positive_int("MOONJUST_PID"),
        num_cpus?=portable_positive_int("MOONJUST_NUM_CPUS"),
        executable?=@env.get_env_var("MOONJUST_EXECUTABLE"),
      )
      portable_platform_cache.val = Some(value)
      value
    }
  }
}

///|
fn windows_powershell() -> String {
  @env.get_env_var("SystemRoot").unwrap_or("C:\\Windows") +
  "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
}

///|
async fn portable_terminal() -> @host.TerminalInfo noraise {
  if portable_terminal_cache.val is Some(value) {
    return value
  }
  let mask = try {
    let (program, args) = if @async.platform is Windows {
      (
        windows_powershell(),
        [
          "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "exit (([int](![Console]::IsInputRedirected)) + 2*([int](![Console]::IsOutputRedirected)) + 4*([int](![Console]::IsErrorRedirected)))",
        ],
      )
    } else {
      (
        "/bin/sh",
        [
          "-c", "n=0; test -t 0 && n=1; test -t 1 && n=$((n+2)); test -t 2 && n=$((n+4)); exit $n",
        ],
      )
    }
    @process.run(program, args, stdin=Inherit, stdout=Inherit, stderr=Inherit, accepted_exit_code=code => {
      code >= 0 && code <= 7
    }).exit_code
  } catch {
    _ => 0
  }
  let value = @host.TerminalInfo::new(
    (mask & 1) != 0,
    (mask & 2) != 0,
    (mask & 4) != 0,
    (mask & 6) != 0,
  )
  portable_terminal_cache.val = Some(value)
  value
}

///|
pub impl @host.HostEnv for ExecutionFs with fn current_dir(_self : ExecutionFs) -> @path.PathValue raise @host.HostError {
  portable_current_dir()
}

///|
pub impl @host.HostClock for ExecutionFs with fn now_millis(_self : ExecutionFs) -> Int64 raise @host.HostError {
  @env.now().reinterpret_as_int64()
}

///|
pub impl @host.HostClock for ExecutionFs with fn local_offset_seconds(_, millis) -> Int32 raise @host.HostError {
  let tz = @env.get_env_var("TZ")
  let name = tz.unwrap_or("")
  if name is ("UTC" | "Etc/UTC" | "GMT" | "UTC0" | "GMT0") {
    return 0
  }
  try {
    if @async.platform is Windows {
      let cmd = "[TimeZoneInfo]::Local.GetUtcOffset([DateTimeOffset]::FromUnixTimeMilliseconds(" +
        millis.to_string() +
        ")).TotalSeconds"
      let output = @process.run(
        windows_powershell(),
        ["-NoProfile", "-NonInteractive", "-Command", cmd],
        stdout=Collect,
        stderr=Discard,
      )
      return @string.parse_int(output.stdout_text().trim())
    }
    if tz == Some("") {
      return 0
    }
    let zone = unix_local_zone(name)
    @time.ZonedDateTime::from_unix_second(millis / 1000L, zone~)
    .offset()
    .seconds()
  } catch {
    _ => raise CapabilityUnavailable(Clock)
  }
}

///|
pub impl @host.HostRandom for ExecutionFs with fn random_bytes(
  _self : ExecutionFs,
  count : Int32,
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
pub impl @host.HostTerminal for ExecutionFs with fn terminal_info(
  _self : ExecutionFs,
) -> @host.TerminalInfo raise @host.HostError {
  portable_terminal()
}

///|
pub impl @host.HostPlatform for ExecutionFs with fn platform_info(
  _self : ExecutionFs,
) -> @host.PlatformInfo raise @host.HostError {
  portable_platform()
}

///|
fn read_error(error : Error, path : @path.PathValue) -> @host.HostError {
  match error {
    @os_error.OsError(NotFound, ..) => NotFound(path)
    @os_error.OsError(AccessDenied, ..) =>
      PermissionDenied(FsRead, detail=error.to_string())
    _ => InvalidInput(error.to_string())
  }
}

///|
pub impl @host.HostFs for ExecutionFs with fn file_size(_self, path) -> Int64 raise @host.HostError {
  try {
    let file = @async_fs.open(path.as_string(), mode=ReadOnly)
    defer file.close()
    file.size()
  } catch {
    error => raise read_error(error, path)
  }
}

///|
pub impl @host.HostFs for ExecutionFs with fn can_execute(_self, path) -> Bool raise @host.HostError {
  @async_fs.can_execute(path.as_string()) catch {
    error => raise read_error(error, path)
  }
}
