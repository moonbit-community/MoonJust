///|
/// File operations required by the pure application core.
pub(open) trait HostFs {
  fn read_file(Self, @path.PathValue) -> Bytes raise HostError
  fn write_file(Self, @path.PathValue, Bytes) -> Unit raise HostError
  fn file_exists(Self, @path.PathValue) -> Bool raise HostError
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
