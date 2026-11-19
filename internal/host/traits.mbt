///|
/// File operations required by the pure application core.
pub(open) trait HostFs {
  async fn read_source(Self, @path.PathValue, Int32) -> Bytes raise HostError
  async fn read_file(Self, @path.PathValue) -> Bytes raise HostError
  async fn read_file_range(Self, @path.PathValue, Int64, Int32) -> Bytes raise HostError
  fn write_file(Self, @path.PathValue, Bytes) -> Unit raise HostError
  async fn file_exists(Self, @path.PathValue) -> Bool raise HostError
  async fn read_dir(Self, @path.PathValue) -> Array[String] raise HostError
  async fn file_size(Self, @path.PathValue) -> Int64 raise HostError
  async fn can_execute(Self, @path.PathValue) -> Bool raise HostError
  async fn metadata(Self, @path.PathValue) -> FileMetadata raise HostError
  async fn canonicalize(Self, @path.PathValue) -> @path.PathValue raise HostError
}

///|
/// Temporary-script lifecycle for the Wasm runtime.
/// `executable` requests mode 0700 at creation time where supported.
pub(open) trait HostScriptTemp {
  async fn create_script_temp(
    Self,
    @path.PathValue,
    String,
    String,
    Bytes,
    Bool,
  ) -> @path.PathValue raise HostError
  async fn remove_script_temp(Self, @path.PathValue) -> Unit raise HostError
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
#derive(Eq, Debug)
pub struct CacheLease {
  directory : @path.PathValue
  digest : String
  token : Int32
}

///|
pub fn CacheLease::new(
  directory : @path.PathValue,
  digest : String,
  token : Int32,
) -> CacheLease {
  { directory, digest, token, }
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
pub fn CacheLease::token(self : CacheLease) -> Int32 {
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
  async fn clean_cache(Self, @path.PathValue, String?) -> Int32 raise HostError
}

///|
/// Environment lookup and the invocation working directory.
pub(open) trait HostEnv {
  fn env_get(Self, String) -> String? raise HostError
  fn env_entries(Self) -> Array[(String, String)] raise HostError
  fn current_dir(Self) -> @path.PathValue raise HostError
}

///|
/// Structured child-process execution. Cancellation of
/// the surrounding task must terminate the child before this method returns.
pub(open) trait HostProcess {
  async fn run_process(Self, CommandSpec) -> ProcessResult raise HostError
}

///|
/// Ordered runtime output which is not produced by a child process.
pub(open) trait HostAsyncOutput {
  async fn write_output(Self, OutputStream, Bytes) -> Int32 raise HostError
}

///|
/// Wall-clock time represented as Unix milliseconds.
pub(open) trait HostClock {
  fn now_millis(Self) -> Int64 raise HostError
  async fn local_offset_seconds(Self, Int64) -> Int32 raise HostError
}

///|
/// Host-provided random bytes.
pub(open) trait HostRandom {
  fn random_bytes(Self, Int32) -> Bytes raise HostError
}

///|
/// Terminal capability observations.
pub(open) trait HostTerminal {
  async fn terminal_info(Self) -> TerminalInfo raise HostError
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
