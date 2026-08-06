///|
/// File operations required by the pure application core.
pub(open) trait HostFs {
  fn read_file(Self, @path.PathValue) -> Bytes raise HostError
  fn read_file_range(Self, @path.PathValue, Int64, Int) -> Bytes raise HostError
  fn write_file(Self, @path.PathValue, Bytes) -> Unit raise HostError
  fn file_exists(Self, @path.PathValue) -> Bool raise HostError
  fn read_dir(Self, @path.PathValue) -> Array[String] raise HostError
  fn metadata(Self, @path.PathValue) -> FileMetadata raise HostError
  fn canonicalize(Self, @path.PathValue) -> @path.PathValue raise HostError
}

///|
/// Pull a file through a bounded buffer. The callback observes chunks in file
/// order and never receives more than `chunk_size` bytes.
pub fn[T : HostFs] stream_file(
  host : T,
  path : @path.PathValue,
  consume : (Bytes) -> Unit,
  chunk_size? : Int = 64 * 1024,
) -> Unit raise HostError {
  if chunk_size <= 0 {
    raise InvalidInput("chunk size must be positive")
  }
  let metadata = HostFs::metadata(host, path)
  if !metadata.is_file() {
    raise InvalidInput("stream source must be a file")
  }
  let mut offset = 0L
  while offset < metadata.size() {
    let remaining = metadata.size() - offset
    let length = if remaining < chunk_size.to_int64() {
      remaining.to_int()
    } else {
      chunk_size
    }
    let bytes = HostFs::read_file_range(host, path, offset, length)
    if bytes.length() == 0 || bytes.length() > length {
      raise InvalidInput("host returned an invalid file range")
    }
    consume(bytes)
    offset += bytes.length().to_int64()
  }
  if metadata.size() == 0L {
    consume(b"")
  }
}

///|
/// Compatibility collector for callers that explicitly need all chunks.
pub fn[T : HostFs] read_file_chunks(
  host : T,
  path : @path.PathValue,
  chunk_size? : Int = 64 * 1024,
) -> Array[Bytes] raise HostError {
  if chunk_size <= 0 {
    raise InvalidInput("chunk size must be positive")
  }
  let chunks : Array[Bytes] = []
  stream_file(host, path, fn(bytes) { chunks.push(bytes) }, chunk_size~)
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
