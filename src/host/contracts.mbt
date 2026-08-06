///|
/// File operations required by the pure application core.
pub(open) trait HostFs {
  fn read_file(Self, @path.PathValue) -> Bytes raise HostError
  fn write_file(Self, @path.PathValue, Bytes) -> Unit raise HostError
  fn file_exists(Self, @path.PathValue) -> Bool raise HostError
  fn read_dir(Self, @path.PathValue) -> Array[String] raise HostError
  fn metadata(Self, @path.PathValue) -> FileMetadata raise HostError
  fn canonicalize(Self, @path.PathValue) -> @path.PathValue raise HostError
}

///|
/// Adapter-neutral chunked view used by hashing and other bounded consumers.
/// Hosts that can stream may replace this helper at their boundary; the
/// default remains deterministic for the in-memory implementation.
pub fn[T : HostFs] read_file_chunks(
  host : T,
  path : @path.PathValue,
  chunk_size? : Int = 64 * 1024,
) -> Array[Bytes] raise HostError {
  if chunk_size <= 0 {
    raise InvalidInput("chunk size must be positive")
  }
  let bytes = HostFs::read_file(host, path)
  let chunks : Array[Bytes] = []
  let mut offset = 0
  while offset < bytes.length() {
    let end = Int::min(offset + chunk_size, bytes.length())
    chunks.push(bytes[offset:end].to_owned())
    offset = end
  }
  if chunks.is_empty() {
    chunks.push(b"")
  }
  chunks
}

///|
/// Environment lookup and the invocation working directory.
pub(open) trait HostEnv {
  fn env_get(Self, String) -> String? raise HostError
  fn current_dir(Self) -> @path.PathValue raise HostError
}

///|
/// Structured child-process execution.
pub(open) trait HostProcess {
  fn run_process(Self, CommandSpec) -> ProcessOutput raise HostError
}

///|
/// Wall-clock time represented as Unix milliseconds.
pub(open) trait HostClock {
  fn now_millis(Self) -> Int64 raise HostError
}

///|
/// Host-provided random bytes.
pub(open) trait HostRandom {
  fn random_bytes(Self, Int) -> Bytes raise HostError
}

///|
/// Terminal capability observations.
pub(open) trait HostTerminal {
  fn terminal_info(Self) -> TerminalInfo raise HostError
}

///|
/// Non-blocking delivery of pending host signals.
pub(open) trait HostSignal {
  fn pending_signal(Self) -> SignalKind? raise HostError
}

///|
/// Runtime platform facts.
pub(open) trait HostPlatform {
  fn platform_info(Self) -> PlatformInfo raise HostError
}
