///|
/// In-memory implementation of every host contract for deterministic tests.
pub struct FakeHost {
  denied : Set[HostCapability]
  unavailable : Set[HostCapability]
  files : Map[@path.PathValue, Bytes]
  mut temp_serial : Int
  mut fail_next_persist : Bool
  canonical_paths : Map[@path.PathValue, @path.PathValue]
  environment : Map[String, String]
  mut cwd : @path.PathValue
  mut clock_millis : Int64
  mut random_stream : Bytes
  mut random_offset : Int
  expected_commands : Array[CommandSpec]
  expected_outputs : Array[ProcessOutput]
  process_calls : Array[CommandSpec]
  mut terminal : TerminalInfo
  signals : Array[SignalKind]
  mut platform : PlatformInfo
}

///|
pub fn FakeHost::new(
  cwd : @path.PathValue,
  platform : PlatformInfo,
) -> FakeHost {
  {
    denied: Set([]),
    unavailable: Set([]),
    files: Map([]),
    temp_serial: 0,
    fail_next_persist: false,
    canonical_paths: Map([]),
    environment: Map([]),
    cwd,
    clock_millis: 0L,
    random_stream: b"",
    random_offset: 0,
    expected_commands: [],
    expected_outputs: [],
    process_calls: [],
    terminal: TerminalInfo::new(false, false, false, false),
    signals: [],
    platform,
  }
}

///|
fn FakeHost::require(
  self : FakeHost,
  capability : HostCapability,
) -> Unit raise HostError {
  if self.denied.contains(capability) {
    raise CapabilityDenied(capability)
  }
  if self.unavailable.contains(capability) {
    raise CapabilityUnavailable(capability)
  }
}

///|
pub fn FakeHost::deny(self : FakeHost, capability : HostCapability) -> Unit {
  self.denied.add(capability)
}

///|
pub fn FakeHost::allow(self : FakeHost, capability : HostCapability) -> Unit {
  self.denied.remove(capability)
}

///|
pub fn FakeHost::mark_unavailable(
  self : FakeHost,
  capability : HostCapability,
) -> Unit {
  self.unavailable.add(capability)
}

///|
pub fn FakeHost::mark_available(
  self : FakeHost,
  capability : HostCapability,
) -> Unit {
  self.unavailable.remove(capability)
}

///|
pub fn FakeHost::put_file(
  self : FakeHost,
  path : @path.PathValue,
  contents : Bytes,
) -> Unit {
  self.files[path] = contents
}

///|
pub fn FakeHost::fail_next_persist(self : FakeHost) -> Unit {
  self.fail_next_persist = true
}

///|
/// Configure a deterministic symlink-like identity for graph tests.
pub fn FakeHost::set_canonical(
  self : FakeHost,
  path : @path.PathValue,
  canonical : @path.PathValue,
) -> Unit {
  self.canonical_paths[path] = canonical
}

///|
pub fn FakeHost::set_env(self : FakeHost, key : String, value : String) -> Unit {
  self.environment[key] = value
}

///|
pub fn FakeHost::set_current_dir(
  self : FakeHost,
  cwd : @path.PathValue,
) -> Unit {
  self.cwd = cwd
}

///|
pub fn FakeHost::set_clock_millis(self : FakeHost, value : Int64) -> Unit {
  self.clock_millis = value
}

///|
pub fn FakeHost::set_random_stream(self : FakeHost, bytes : Bytes) -> Unit {
  self.random_stream = bytes
  self.random_offset = 0
}

///|
pub fn FakeHost::expect_process(
  self : FakeHost,
  command : CommandSpec,
  output : ProcessOutput,
) -> Unit {
  self.expected_commands.push(command)
  self.expected_outputs.push(output)
}

///|
pub fn FakeHost::process_calls(self : FakeHost) -> ArrayView[CommandSpec] {
  self.process_calls[:]
}

///|
pub fn FakeHost::pending_process_expectations(self : FakeHost) -> Int {
  self.expected_commands.length()
}

///|
pub fn FakeHost::set_terminal(self : FakeHost, terminal : TerminalInfo) -> Unit {
  self.terminal = terminal
}

///|
pub fn FakeHost::push_signal(self : FakeHost, signal : SignalKind) -> Unit {
  self.signals.push(signal)
}

///|
pub fn FakeHost::set_platform(self : FakeHost, platform : PlatformInfo) -> Unit {
  self.platform = platform
}

///|
pub impl HostFs for FakeHost with fn read_file(
  self : FakeHost,
  path : @path.PathValue,
) -> Bytes raise HostError {
  self.require(FsRead)
  match self.files.get(path) {
    Some(contents) => contents
    None => raise NotFound(path)
  }
}

///|
pub impl HostFs for FakeHost with fn read_file_range(
  self : FakeHost,
  path : @path.PathValue,
  offset : Int64,
  length : Int,
) -> Bytes raise HostError {
  self.require(FsRead)
  if offset < 0L || length < 0 {
    raise InvalidInput("file range must not be negative")
  }
  let contents = match self.files.get(path) {
    Some(value) => value
    None => raise NotFound(path)
  }
  if offset >= contents.length().to_int64() || length == 0 {
    return b""
  }
  let start = offset.to_int()
  let end = Int::min(start + length, contents.length())
  contents[start:end].to_owned()
}

///|
pub impl HostFs for FakeHost with fn write_file(
  self : FakeHost,
  path : @path.PathValue,
  contents : Bytes,
) -> Unit raise HostError {
  self.require(FsWrite)
  self.files[path] = contents
}

///|
pub impl HostFs for FakeHost with fn file_exists(
  self : FakeHost,
  path : @path.PathValue,
) -> Bool raise HostError {
  self.require(FsRead)
  self.files.contains(path)
}

///|
pub impl HostFs for FakeHost with fn read_dir(
  self : FakeHost,
  path : @path.PathValue,
) -> Array[String] raise HostError {
  self.require(FsRead)
  let prefix = if path.as_string() == "." {
    "."
  } else {
    path.as_string() + path.flavor().separator().to_string()
  }
  let result : Array[String] = []
  for file in self.files.keys() {
    let value = file.as_string()
    if value.has_prefix(prefix) {
      let rest = value.view(start_offset=prefix.length()).to_owned()
      if !rest.contains(path.flavor().separator().to_string()) &&
        !result.contains(rest) {
        result.push(rest)
      }
    }
  }
  result.sort()
  result
}

///|
pub impl HostFs for FakeHost with fn metadata(
  self : FakeHost,
  path : @path.PathValue,
) -> FileMetadata raise HostError {
  self.require(FsRead)
  match self.files.get(path) {
    Some(contents) =>
      FileMetadata::new(true, false, contents.length().to_int64())
    None => raise NotFound(path)
  }
}

///|
pub impl HostFs for FakeHost with fn canonicalize(
  self : FakeHost,
  path : @path.PathValue,
) -> @path.PathValue raise HostError {
  self.require(FsRead)
  self.canonical_paths.get(path).unwrap_or(path)
}

///|
pub impl HostFs for FakeHost with fn persist_temp_file(
  self : FakeHost,
  temporary : @path.PathValue,
  destination : @path.PathValue,
  overwrite : Bool,
) -> Unit raise HostError {
  self.require(FsWrite)
  if self.fail_next_persist {
    self.fail_next_persist = false
    raise InvalidInput("injected atomic persist failure")
  }
  guard self.files.get(temporary) is Some(contents) else {
    raise NotFound(temporary)
  }
  if !overwrite && self.files.contains(destination) {
    raise AlreadyExists(destination)
  }
  self.files[destination] = contents
  self.files.remove(temporary)
}

///|
pub impl HostTemp for FakeHost with fn create_temp_file(
  self : FakeHost,
  directory : @path.PathValue,
  prefix : String,
  contents : Bytes,
) -> @path.PathValue raise HostError {
  self.require(FsWrite)
  if prefix == "" || prefix.contains("/") || prefix.contains("\\") {
    raise InvalidInput("temporary file prefix must be a file name prefix")
  }
  for _ in 0..<1024 {
    let name = @path.PathValue::new(
      prefix + self.temp_serial.to_string(),
      directory.flavor(),
    ) catch {
      _ => raise InvalidInput("invalid temporary file name")
    }
    self.temp_serial += 1
    let candidate = directory.join(name) catch {
      _ => raise InvalidInput("temporary file path flavor mismatch")
    }
    if !self.files.contains(candidate) {
      self.files[candidate] = contents
      return candidate
    }
  }
  raise InvalidInput("temporary file namespace exhausted")
}

///|
pub impl HostTemp for FakeHost with fn remove_temp_file(
  self : FakeHost,
  path : @path.PathValue,
) -> Unit raise HostError {
  self.require(FsWrite)
  if !self.files.contains(path) {
    raise NotFound(path)
  }
  self.files.remove(path)
}

///|
pub impl HostAtomicFs for FakeHost with fn write_file_atomic(
  self : FakeHost,
  path : @path.PathValue,
  contents : Bytes,
  overwrite : Bool,
) -> Unit raise HostError {
  write_file_atomic(self, path, contents, overwrite~)
}

///|
pub impl HostEnv for FakeHost with fn env_get(self : FakeHost, key : String) -> String? raise HostError {
  self.require(Environment)
  self.environment.get(key)
}

///|
pub impl HostEnv for FakeHost with fn current_dir(self : FakeHost) -> @path.PathValue raise HostError {
  self.require(Environment)
  self.cwd
}

///|
pub impl HostProcess for FakeHost with fn run_process(
  self : FakeHost,
  command : CommandSpec,
) -> ProcessOutput raise HostError {
  self.require(Process)
  self.process_calls.push(command)
  if self.expected_commands.is_empty() {
    raise UnexpectedProcess(command)
  }
  let expected = self.expected_commands.remove(0)
  let output = self.expected_outputs.remove(0)
  if expected != command {
    raise ProcessMismatch(expected~, actual=command)
  }
  output
}

///|
pub impl HostClock for FakeHost with fn now_millis(self : FakeHost) -> Int64 raise HostError {
  self.require(Clock)
  self.clock_millis
}

///|
pub impl HostRandom for FakeHost with fn random_bytes(
  self : FakeHost,
  count : Int,
) -> Bytes raise HostError {
  self.require(Random)
  if count < 0 {
    raise InvalidInput("random byte count must not be negative")
  }
  let remaining = self.random_stream.length() - self.random_offset
  if count > remaining {
    raise RandomExhausted(requested=count, remaining~)
  }
  let end = self.random_offset + count
  let result = self.random_stream[self.random_offset:end].to_owned()
  self.random_offset = end
  result
}

///|
pub impl HostTerminal for FakeHost with fn terminal_info(self : FakeHost) -> TerminalInfo raise HostError {
  self.require(Terminal)
  self.terminal
}

///|
pub impl HostSignal for FakeHost with fn pending_signal(self : FakeHost) -> SignalKind? raise HostError {
  self.require(Signal)
  if self.signals.is_empty() {
    None
  } else {
    Some(self.signals.remove(0))
  }
}

///|
pub impl HostPlatform for FakeHost with fn platform_info(self : FakeHost) -> PlatformInfo raise HostError {
  self.require(Platform)
  self.platform
}
