///|
/// In-memory implementation of every host contract for deterministic tests.
pub struct FakeHost {
  denied : Set[@host.HostCapability]
  unavailable : Set[@host.HostCapability]
  files : Map[@path.PathValue, Bytes]
  mut temp_serial : Int
  mut fail_next_persist : Bool
  script_temp_creations : Array[(@path.PathValue, Bytes)]
  executable_calls : Array[@path.PathValue]
  canonical_paths : Map[@path.PathValue, @path.PathValue]
  environment : Map[String, String]
  mut cwd : @path.PathValue
  mut clock_millis : Int64
  mut random_stream : Bytes
  mut random_offset : Int
  expected_commands : Array[@host.CommandSpec]
  expected_outputs : Array[@host.ProcessResult]
  process_calls : Array[@host.CommandSpec]
  output_events : Array[(@host.OutputStream, Bytes)]
  mut terminal : @host.TerminalInfo
  signals : Array[@host.SignalKind]
  mut platform : @host.PlatformInfo
  cache_entries : Map[String, Bytes]
  cache_leases : Map[Int, String]
  mut cache_token : Int
}

///|
pub fn FakeHost::new(
  cwd : @path.PathValue,
  platform : @host.PlatformInfo,
) -> FakeHost {
  {
    denied: Set([]),
    unavailable: Set([]),
    files: Map([]),
    temp_serial: 0,
    fail_next_persist: false,
    script_temp_creations: [],
    executable_calls: [],
    canonical_paths: Map([]),
    environment: Map([]),
    cwd,
    clock_millis: 0L,
    random_stream: b"",
    random_offset: 0,
    expected_commands: [],
    expected_outputs: [],
    process_calls: [],
    output_events: [],
    terminal: @host.TerminalInfo::new(false, false, false, false),
    signals: [],
    platform,
    cache_entries: Map([]),
    cache_leases: Map([]),
    cache_token: 0,
  }
}

///|
fn cache_storage_key(directory : @path.PathValue, digest : String) -> String {
  directory.as_string() + "|" + digest
}

///|
pub fn FakeHost::seed_cache_manifest(
  self : FakeHost,
  directory : @path.PathValue,
  digest : String,
  contents : Bytes,
) -> Unit {
  self.cache_entries[cache_storage_key(directory, digest)] = contents
}

///|
pub fn FakeHost::cache_manifest(
  self : FakeHost,
  directory : @path.PathValue,
  digest : String,
) -> Bytes? {
  self.cache_entries.get(cache_storage_key(directory, digest))
}

///|
pub fn FakeHost::cache_manifest_digests(
  self : FakeHost,
  directory : @path.PathValue,
) -> Array[String] {
  let prefix = directory.as_string() + "|"
  let result : Array[String] = []
  for key, _ in self.cache_entries {
    if key.has_prefix(prefix) {
      result.push(key[prefix.length():].to_owned())
    }
  }
  result.sort()
  result
}

///|
pub fn FakeHost::held_cache_leases(self : FakeHost) -> Int {
  self.cache_leases.length()
}

///|
fn FakeHost::require(
  self : FakeHost,
  capability : @host.HostCapability,
) -> Unit raise @host.HostError {
  if self.denied.contains(capability) {
    raise @host.CapabilityDenied(capability)
  }
  if self.unavailable.contains(capability) {
    raise @host.CapabilityUnavailable(capability)
  }
}

///|
pub fn FakeHost::deny(
  self : FakeHost,
  capability : @host.HostCapability,
) -> Unit {
  self.denied.add(capability)
}

///|
pub fn FakeHost::allow(
  self : FakeHost,
  capability : @host.HostCapability,
) -> Unit {
  self.denied.remove(capability)
}

///|
pub fn FakeHost::mark_unavailable(
  self : FakeHost,
  capability : @host.HostCapability,
) -> Unit {
  self.unavailable.add(capability)
}

///|
pub fn FakeHost::mark_available(
  self : FakeHost,
  capability : @host.HostCapability,
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
pub fn FakeHost::script_temp_creations(
  self : FakeHost,
) -> ArrayView[(@path.PathValue, Bytes)] {
  self.script_temp_creations[:]
}

///|
pub fn FakeHost::executable_calls(
  self : FakeHost,
) -> ArrayView[@path.PathValue] {
  self.executable_calls[:]
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
  command : @host.CommandSpec,
  output : @host.ProcessResult,
) -> Unit {
  self.expected_commands.push(command)
  self.expected_outputs.push(output)
}

///|
pub fn FakeHost::process_calls(self : FakeHost) -> ArrayView[@host.CommandSpec] {
  self.process_calls[:]
}

///|
pub fn FakeHost::output_events(
  self : FakeHost,
) -> ArrayView[(@host.OutputStream, Bytes)] {
  self.output_events[:]
}

///|
pub fn FakeHost::pending_process_expectations(self : FakeHost) -> Int {
  self.expected_commands.length()
}

///|
pub fn FakeHost::set_terminal(
  self : FakeHost,
  terminal : @host.TerminalInfo,
) -> Unit {
  self.terminal = terminal
}

///|
pub fn FakeHost::push_signal(
  self : FakeHost,
  signal : @host.SignalKind,
) -> Unit {
  self.signals.push(signal)
}

///|
pub fn FakeHost::set_platform(
  self : FakeHost,
  platform : @host.PlatformInfo,
) -> Unit {
  self.platform = platform
}

///|
pub impl @host.HostFs for FakeHost with fn read_file(
  self : FakeHost,
  path : @path.PathValue,
) -> Bytes raise @host.HostError {
  self.require(@host.FsRead)
  match self.files.get(path) {
    Some(contents) => contents
    None => raise @host.NotFound(path)
  }
}

///|
pub impl @host.HostFs for FakeHost with fn read_file_range(
  self : FakeHost,
  path : @path.PathValue,
  offset : Int64,
  length : Int,
) -> Bytes raise @host.HostError {
  self.require(@host.FsRead)
  if offset < 0L || length < 0 {
    raise @host.InvalidInput("file range must not be negative")
  }
  let contents = match self.files.get(path) {
    Some(value) => value
    None => raise @host.NotFound(path)
  }
  if offset >= contents.length().to_int64() || length == 0 {
    return b""
  }
  let start = offset.to_int()
  let end = Int::min(start + length, contents.length())
  contents[start:end].to_owned()
}

///|
pub impl @host.HostSourceReader for FakeHost with fn read_source(
  self : FakeHost,
  path : @path.PathValue,
  max_bytes : Int,
) -> Bytes raise @host.HostError {
  if max_bytes < 0 {
    raise @host.InvalidInput("source byte limit must not be negative")
  }
  if max_bytes == 0x7fffffff {
    raise @host.InvalidInput("source byte limit is too large")
  }
  let contents = @host.HostFs::read_file(self, path)
  contents[:Int::min(contents.length(), max_bytes + 1)].to_owned()
}

///|
pub impl @host.HostFs for FakeHost with fn write_file(
  self : FakeHost,
  path : @path.PathValue,
  contents : Bytes,
) -> Unit raise @host.HostError {
  self.require(@host.FsWrite)
  self.files[path] = contents
}

///|
pub impl @host.HostFs for FakeHost with fn file_exists(
  self : FakeHost,
  path : @path.PathValue,
) -> Bool raise @host.HostError {
  self.require(@host.FsRead)
  self.files.contains(path)
}

///|
pub impl @host.HostFs for FakeHost with fn read_dir(
  self : FakeHost,
  path : @path.PathValue,
) -> Array[String] raise @host.HostError {
  self.require(@host.FsRead)
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
pub impl @host.HostFs for FakeHost with fn metadata(
  self : FakeHost,
  path : @path.PathValue,
) -> @host.FileMetadata raise @host.HostError {
  self.require(@host.FsRead)
  match self.files.get(path) {
    Some(contents) =>
      @host.FileMetadata::new(true, false, contents.length().to_int64())
    None => raise @host.NotFound(path)
  }
}

///|
pub impl @host.HostFs for FakeHost with fn canonicalize(
  self : FakeHost,
  path : @path.PathValue,
) -> @path.PathValue raise @host.HostError {
  self.require(@host.FsRead)
  self.canonical_paths.get(path).unwrap_or(path)
}

///|
pub impl @host.HostFs for FakeHost with fn persist_temp_file(
  self : FakeHost,
  temporary : @path.PathValue,
  destination : @path.PathValue,
  overwrite : Bool,
) -> Unit raise @host.HostError {
  self.require(@host.FsWrite)
  if self.fail_next_persist {
    self.fail_next_persist = false
    raise @host.InvalidInput("injected atomic persist failure")
  }
  guard self.files.get(temporary) is Some(contents) else {
    raise @host.NotFound(temporary)
  }
  if !overwrite && self.files.contains(destination) {
    raise AlreadyExists(destination)
  }
  self.files[destination] = contents
  self.files.remove(temporary)
}

///|
pub impl @host.HostTemp for FakeHost with fn create_temp_file(
  self : FakeHost,
  directory : @path.PathValue,
  prefix : String,
  contents : Bytes,
) -> @path.PathValue raise @host.HostError {
  self.require(@host.FsWrite)
  if prefix == "" || prefix.contains("/") || prefix.contains("\\") {
    raise @host.InvalidInput("temporary file prefix must be a file name prefix")
  }
  for _ in 0..<1024 {
    let name = @path.PathValue::new(
      prefix + self.temp_serial.to_string(),
      directory.flavor(),
    ) catch {
      _ => raise @host.InvalidInput("invalid temporary file name")
    }
    self.temp_serial += 1
    let candidate = directory.join(name) catch {
      _ => raise @host.InvalidInput("temporary file path flavor mismatch")
    }
    if !self.files.contains(candidate) {
      self.files[candidate] = contents
      return candidate
    }
  }
  raise @host.InvalidInput("temporary file namespace exhausted")
}

///|
pub impl @host.HostTemp for FakeHost with fn remove_temp_file(
  self : FakeHost,
  path : @path.PathValue,
) -> Unit raise @host.HostError {
  self.require(@host.FsWrite)
  if !self.files.contains(path) {
    raise @host.NotFound(path)
  }
  self.files.remove(path)
}

///|
pub impl @host.HostScriptTemp for FakeHost with fn create_script_temp(
  self : FakeHost,
  directory : @path.PathValue,
  stem : String,
  extension : String,
  contents : Bytes,
) -> @path.PathValue raise @host.HostError {
  self.require(@host.FsWrite)
  if stem == "" ||
    stem.contains("/") ||
    stem.contains("\\") ||
    extension.contains("/") ||
    extension.contains("\\") {
    raise @host.InvalidInput("invalid temporary script name")
  }
  for _ in 0..<1024 {
    let name = @path.PathValue::new(
      stem + "." + self.temp_serial.to_string() + extension,
      directory.flavor(),
    ) catch {
      _ => raise @host.InvalidInput("invalid temporary script name")
    }
    self.temp_serial += 1
    let candidate = directory.join(name) catch {
      _ => raise @host.InvalidInput("temporary script path flavor mismatch")
    }
    if !self.files.contains(candidate) {
      self.files[candidate] = contents
      self.script_temp_creations.push((candidate, contents))
      return candidate
    }
  }
  raise @host.InvalidInput("temporary script namespace exhausted")
}

///|
pub impl @host.HostScriptTemp for FakeHost with fn remove_script_temp(
  self : FakeHost,
  path : @path.PathValue,
) -> Unit raise @host.HostError {
  @host.HostTemp::remove_temp_file(self, path)
}

///|
pub impl @host.HostExecutable for FakeHost with fn set_executable(
  self : FakeHost,
  path : @path.PathValue,
) -> Unit raise @host.HostError {
  self.require(@host.FsWrite)
  if !self.files.contains(path) {
    raise @host.NotFound(path)
  }
  self.executable_calls.push(path)
}

///|
pub impl @host.HostAsyncScriptTemp for FakeHost with fn create_script_temp_async(
  self : FakeHost,
  directory : @path.PathValue,
  stem : String,
  extension : String,
  contents : Bytes,
  executable : Bool,
) -> @path.PathValue raise @host.HostError {
  let path = @host.HostScriptTemp::create_script_temp(
    self, directory, stem, extension, contents,
  )
  if executable {
    @host.HostExecutable::set_executable(self, path)
  }
  path
}

///|
pub impl @host.HostAsyncScriptTemp for FakeHost with fn remove_script_temp_async(
  self : FakeHost,
  path : @path.PathValue,
) -> Unit raise @host.HostError {
  @host.HostScriptTemp::remove_script_temp(self, path)
}

///|
pub impl @host.HostAtomicFs for FakeHost with fn write_file_atomic(
  self : FakeHost,
  path : @path.PathValue,
  contents : Bytes,
  overwrite : Bool,
) -> Unit raise @host.HostError {
  @host_fs.write_file_atomic(self, path, contents, overwrite~)
}

///|
fn valid_cache_digest(digest : String) -> Bool {
  if digest.length() != 64 {
    return false
  }
  for character in digest {
    if !(character >= '0' && character <= '9') &&
      !(character >= 'a' && character <= 'f') {
      return false
    }
  }
  true
}

///|
pub impl @host.HostCacheStore for FakeHost with fn acquire_cache_lease(
  self : FakeHost,
  directory : @path.PathValue,
  digest : String,
) -> @host.CacheLease raise @host.HostError {
  self.require(@host.FsWrite)
  if !valid_cache_digest(digest) {
    raise @host.InvalidInput("invalid cache digest")
  }
  let key = cache_storage_key(directory, digest)
  for _, held in self.cache_leases {
    if held == key {
      raise @host.InvalidInput("cache digest is already locked")
    }
  }
  let token = self.cache_token
  self.cache_token += 1
  self.cache_leases[token] = key
  @host.CacheLease::new(directory, digest, token)
}

///|
pub impl @host.HostCacheStore for FakeHost with fn read_cache_manifest(
  self : FakeHost,
  lease : @host.CacheLease,
) -> Bytes? raise @host.HostError {
  let key = cache_storage_key(lease.directory(), lease.digest())
  if self.cache_leases.get(lease.token()) != Some(key) {
    raise @host.InvalidInput("cache lease is not held")
  }
  match self.cache_entries.get(key) {
    Some(contents) if contents.length() > @cache.MAX_MANIFEST_BYTES + 1 =>
      Some(contents[:@cache.MAX_MANIFEST_BYTES + 1].to_owned())
    value => value
  }
}

///|
pub impl @host.HostCacheStore for FakeHost with fn write_cache_manifest(
  self : FakeHost,
  lease : @host.CacheLease,
  contents : Bytes,
) -> Unit raise @host.HostError {
  let key = cache_storage_key(lease.directory(), lease.digest())
  if self.cache_leases.get(lease.token()) != Some(key) {
    raise @host.InvalidInput("cache lease is not held")
  }
  if contents.length() > @cache.MAX_MANIFEST_BYTES {
    raise @host.InvalidInput("cache manifest exceeds size limit")
  }
  self.cache_entries[key] = contents
}

///|
pub impl @host.HostCacheStore for FakeHost with fn release_cache_lease(
  self : FakeHost,
  lease : @host.CacheLease,
) -> Unit raise @host.HostError {
  let key = cache_storage_key(lease.directory(), lease.digest())
  if self.cache_leases.get(lease.token()) != Some(key) {
    raise @host.InvalidInput("cache lease is not held")
  }
  self.cache_leases.remove(lease.token())
}

///|
pub impl @host.HostCacheStore for FakeHost with fn clean_cache(
  self : FakeHost,
  directory : @path.PathValue,
  recipe_prefix : String?,
) -> Int raise @host.HostError {
  self.require(@host.FsWrite)
  let prefix = directory.as_string() + "|"
  let removable : Array[String] = []
  for key, _ in self.cache_entries {
    if key.has_prefix(prefix) &&
      valid_cache_digest(key[prefix.length():].to_owned()) {
      let selected = match recipe_prefix {
        None => true
        Some(prefix) => {
          guard self.cache_entries.get(key) is Some(bytes) else { false }
          if bytes.is_empty() {
            true
          } else {
            let text = @utf8.decode(bytes) catch {
              _ => raise @host.InvalidInput("failed to decode cache manifest")
            }
            let manifest = @cache.decode_manifest(text) catch {
              _ => raise @host.InvalidInput("failed to parse cache manifest")
            }
            manifest.recipe() == prefix ||
            manifest.recipe().has_prefix(prefix + "::")
          }
        }
      }
      if selected {
        removable.push(key)
      }
    }
  }
  for key in removable {
    self.cache_entries.remove(key)
  }
  removable.length()
}

///|
pub impl @host.HostEnv for FakeHost with fn env_get(
  self : FakeHost,
  key : String,
) -> String? raise @host.HostError {
  self.require(@host.Environment)
  self.environment.get(key)
}

///|
pub impl @host.HostEnv for FakeHost with fn env_entries(self : FakeHost) -> Array[
  (String, String),
] raise @host.HostError {
  self.require(@host.Environment)
  let keys = self.environment.keys().collect()
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
  keys.map(fn(key) { (key, self.environment[key]) })
}

///|
pub impl @host.HostEnv for FakeHost with fn current_dir(self : FakeHost) -> @path.PathValue raise @host.HostError {
  self.require(@host.Environment)
  self.cwd
}

///|
pub impl @host.HostProcess for FakeHost with fn run_process(
  self : FakeHost,
  command : @host.CommandSpec,
) -> @host.ProcessResult raise @host.HostError {
  self.require(@host.Process)
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
pub impl @host.HostAsyncProcess for FakeHost with fn run_process_async(
  self : FakeHost,
  command : @host.CommandSpec,
) -> @host.ProcessResult raise @host.HostError {
  self.require(@host.Process)
  if command.program() == "/bin/test" && command.arguments().length() == 2 {
    let path = @path.PathValue::new(command.arguments()[1], self.cwd.flavor()) catch {
      _ => raise @host.InvalidInput("invalid fake test path")
    }
    let exists = self.files.contains(path)
    let success = match command.arguments()[0] {
      "-d" => !exists && !@host.HostFs::read_dir(self, path).is_empty()
      "-x" => exists
      _ => false
    }
    return @host.ProcessResult::new(if success { 0 } else { 1 }, b"", b"")
  }
  if command.program() == "/bin/cat" && command.arguments().length() == 1 {
    let path = @path.PathValue::new(command.arguments()[0], self.cwd.flavor()) catch {
      _ => raise @host.InvalidInput("invalid fake cat path")
    }
    return match self.files.get(path) {
      Some(contents) => @host.ProcessResult::new(0, contents, b"")
      None => @host.ProcessResult::new(1, b"", b"")
    }
  }
  @host.HostProcess::run_process(self, command)
}

///|
pub impl @host.HostAsyncOutput for FakeHost with fn write_output(
  self : FakeHost,
  stream : @host.OutputStream,
  bytes : Bytes,
) -> Int raise @host.HostError {
  let length = bytes.length()
  self.output_events.push((stream, bytes))
  length
}

///|
pub impl @host.HostClock for FakeHost with fn now_millis(self : FakeHost) -> Int64 raise @host.HostError {
  self.require(@host.Clock)
  self.clock_millis
}

///|
pub impl @host.HostRandom for FakeHost with fn random_bytes(
  self : FakeHost,
  count : Int,
) -> Bytes raise @host.HostError {
  self.require(@host.Random)
  if count < 0 {
    raise @host.InvalidInput("random byte count must not be negative")
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
pub impl @host.HostTerminal for FakeHost with fn terminal_info(self : FakeHost) -> @host.TerminalInfo raise @host.HostError {
  self.require(@host.Terminal)
  self.terminal
}

///|
pub impl @host.HostSignal for FakeHost with fn pending_signal(self : FakeHost) -> @host.SignalKind? raise @host.HostError {
  self.require(@host.Signal)
  if self.signals.is_empty() {
    None
  } else {
    Some(self.signals.remove(0))
  }
}

///|
pub impl @host.HostPlatform for FakeHost with fn platform_info(self : FakeHost) -> @host.PlatformInfo raise @host.HostError {
  self.require(@host.Platform)
  self.platform
}
