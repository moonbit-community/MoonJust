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
  fn persist_temp_file(Self, @path.PathValue, @path.PathValue, Bool) -> Unit raise HostError
}

///|
/// Bounded asynchronous source access for production loaders. Implementations
/// must never retain more than `max_bytes + 1` bytes before returning so the
/// lexer can report an exact source-limit failure without a full-file read.
pub(open) trait HostSourceReader {
  async fn read_source(Self, @path.PathValue, Int) -> Bytes raise HostError
}

///|
/// Lifecycle for temporary files created beside their eventual destination.
/// Keeping this separate from `HostFs` makes cleanup an explicit obligation.
pub(open) trait HostTemp {
  fn create_temp_file(Self, @path.PathValue, String, Bytes) -> @path.PathValue raise HostError
  fn remove_temp_file(Self, @path.PathValue) -> Unit raise HostError
}

///|
/// Temporary script creation keeps a required filename extension at the end.
/// This is separate from atomic-write temporaries, whose names need no suffix.
pub(open) trait HostScriptTemp {
  fn create_script_temp(Self, @path.PathValue, String, String, Bytes) -> @path.PathValue raise HostError
  fn remove_script_temp(Self, @path.PathValue) -> Unit raise HostError
}

///|
/// Mark a generated script as directly executable where the platform requires
/// it. Windows adapters implement this as a successful no-op.
pub(open) trait HostExecutable {
  fn set_executable(Self, @path.PathValue) -> Unit raise HostError
}

///|
/// Async temporary-script lifecycle for native and wasm execution runtimes.
/// `executable` requests mode 0700 at creation time where supported.
pub(open) trait HostAsyncScriptTemp {
  async fn create_script_temp_async(
    Self,
    @path.PathValue,
    String,
    String,
    Bytes,
    Bool,
  ) -> @path.PathValue raise HostError
  async fn remove_script_temp_async(Self, @path.PathValue) -> Unit raise HostError
}

///|
/// Atomic filesystem transaction available to asynchronous host adapters.
/// Wasm implementations use this contract so moonrun can enforce filesystem
/// policy around create, remove, and rename operations.
pub(open) trait HostAtomicFs {
  async fn write_file_atomic(Self, @path.PathValue, Bytes, Bool) -> Unit raise HostError
}

///|
/// Opaque ownership token for one digest lock. The lock remains owned until
/// the same adapter releases this lease.
pub struct CacheLease {
  directory : @path.PathValue
  digest : String
  token : Int
} derive(Eq, Debug)

///|
pub fn CacheLease::new(
  directory : @path.PathValue,
  digest : String,
  token : Int,
) -> CacheLease {
  { directory, digest, token }
}

///|
pub fn CacheLease::directory(self : CacheLease) -> @path.PathValue {
  self.directory
}

///|
pub fn CacheLease::digest(self : CacheLease) -> String {
  self.digest
}

///|
pub fn CacheLease::token(self : CacheLease) -> Int {
  self.token
}

///|
/// Persistent recipe-cache storage. Implementations hold an exclusive
/// cross-process lock from acquisition through lookup, execution, and commit.
/// Reads return at most `MAX_MANIFEST_BYTES + 1` bytes so callers can reject
/// oversized entries without allocating in proportion to hostile files.
pub(open) trait HostCacheStore {
  async fn acquire_cache_lease(Self, @path.PathValue, String) -> CacheLease raise HostError
  async fn read_cache_manifest(Self, CacheLease) -> Bytes? raise HostError
  async fn write_cache_manifest(Self, CacheLease, Bytes) -> Unit raise HostError
  async fn release_cache_lease(Self, CacheLease) -> Unit raise HostError
  async fn clean_cache(Self, @path.PathValue, String?) -> Int raise HostError
}

///|
/// Persist bytes through a same-directory temporary file. Adapters must create
/// the temporary file exclusively and commit it atomically. A failed commit is
/// followed by a best-effort cleanup without hiding the original failure.
pub fn[T : HostFs + HostTemp] write_file_atomic(
  host : T,
  path : @path.PathValue,
  contents : Bytes,
  overwrite? : Bool = true,
) -> Unit raise HostError {
  let directory = match path.parent() {
    Some(value) => value
    None =>
      raise InvalidInput("atomic write target must have a parent directory")
  }
  let temporary = HostTemp::create_temp_file(
    host, directory, ".moonjust.tmp.", contents,
  )
  errdefer (try HostTemp::remove_temp_file(host, temporary) catch {
    _ => ()
  } noraise {
    _ => ()
  })
  HostFs::persist_temp_file(host, temporary, path, overwrite)
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
  fn env_entries(Self) -> Array[(String, String)] raise HostError
  fn current_dir(Self) -> @path.PathValue raise HostError
}

///|
/// Structured child-process execution.
pub(open) trait HostProcess {
  fn run_process(Self, CommandSpec) -> ProcessResult raise HostError
}

///|
/// Structured process execution for Native and wasm1 runtimes. Cancellation of
/// the surrounding task must terminate the child before this method returns.
pub(open) trait HostAsyncProcess {
  async fn run_process_async(Self, CommandSpec) -> ProcessResult raise HostError
}

///|
/// Ordered runtime output which is not produced by a child process.
pub(open) trait HostAsyncOutput {
  async fn write_output(Self, OutputStream, Bytes) -> Int raise HostError
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
