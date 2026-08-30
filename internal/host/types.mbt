///|
/// Host facilities that may be granted, denied, or unavailable independently.
pub(all) enum HostCapability {
  FsRead
  FsWrite
  Environment
  Process
  Clock
  Random
  Terminal
  Signal
  Platform
} derive(Eq, Hash, Debug)

///|
/// Filesystem facts exposed without leaking adapter-specific stat types.
pub(all) struct FileMetadata {
  is_file : Bool
  is_directory : Bool
  size : Int64
  is_executable : Bool
} derive(Eq, Debug)

///|
pub fn FileMetadata::new(
  is_file : Bool,
  is_directory : Bool,
  size : Int64,
) -> FileMetadata {
  { is_file, is_directory, size, is_executable: is_file, }
}

///|
/// Construct metadata with an explicit executable bit.
pub fn FileMetadata::new_with_executable(
  is_file : Bool,
  is_directory : Bool,
  size : Int64,
  is_executable : Bool,
) -> FileMetadata {
  { is_file, is_directory, size, is_executable, }
}

///|
pub fn FileMetadata::is_file(self : FileMetadata) -> Bool {
  self.is_file
}

///|
pub fn FileMetadata::is_directory(self : FileMetadata) -> Bool {
  self.is_directory
}

///|
pub fn FileMetadata::size(self : FileMetadata) -> Int64 {
  self.size
}

///|
pub fn FileMetadata::is_executable(self : FileMetadata) -> Bool {
  self.is_executable
}

///|
pub(all) enum OperatingSystem {
  Linux
  Macos
  Windows
  Other(String)
} derive(Eq, Hash, Debug)

///|
/// Target facts provided by an adapter instead of compile-time conditionals.
pub struct PlatformInfo {
  operating_system : OperatingSystem
  architecture : String
  path_flavor : @path.PathFlavor
  portable_runtime : Bool
  pid : Int?
  num_cpus : Int?
  executable : String?
} derive(Eq, Debug)

///|
pub fn PlatformInfo::new(
  operating_system : OperatingSystem,
  architecture : String,
  path_flavor : @path.PathFlavor,
  portable_runtime? : Bool = false,
  pid? : Int,
  num_cpus? : Int,
  executable? : String,
) -> PlatformInfo {
  {
    operating_system,
    architecture,
    path_flavor,
    portable_runtime,
    pid,
    num_cpus,
    executable,
  }
}

///|
pub fn PlatformInfo::operating_system(self : PlatformInfo) -> OperatingSystem {
  self.operating_system
}

///|
pub fn PlatformInfo::architecture(self : PlatformInfo) -> String {
  self.architecture
}

///|
pub fn PlatformInfo::path_flavor(self : PlatformInfo) -> @path.PathFlavor {
  self.path_flavor
}

///|
/// Whether filesystem facts come from a portable runtime which cannot expose
/// canonical paths and executable mode bits synchronously.
pub fn PlatformInfo::portable_runtime(self : PlatformInfo) -> Bool {
  self.portable_runtime
}

///|
pub fn PlatformInfo::pid(self : PlatformInfo) -> Int? {
  self.pid
}

///|
pub fn PlatformInfo::num_cpus(self : PlatformInfo) -> Int? {
  self.num_cpus
}

///|
pub fn PlatformInfo::executable(self : PlatformInfo) -> String? {
  self.executable
}

///|
/// Terminal observations supplied by the host adapter.
pub struct TerminalInfo {
  stdin_is_terminal : Bool
  stdout_is_terminal : Bool
  stderr_is_terminal : Bool
  color_supported : Bool
} derive(Eq, Debug)

///|
pub fn TerminalInfo::new(
  stdin_is_terminal : Bool,
  stdout_is_terminal : Bool,
  stderr_is_terminal : Bool,
  color_supported : Bool,
) -> TerminalInfo {
  {
    stdin_is_terminal,
    stdout_is_terminal,
    stderr_is_terminal,
    color_supported,
  }
}

///|
pub fn TerminalInfo::stdin_is_terminal(self : TerminalInfo) -> Bool {
  self.stdin_is_terminal
}

///|
pub fn TerminalInfo::stdout_is_terminal(self : TerminalInfo) -> Bool {
  self.stdout_is_terminal
}

///|
pub fn TerminalInfo::stderr_is_terminal(self : TerminalInfo) -> Bool {
  self.stderr_is_terminal
}

///|
pub fn TerminalInfo::color_supported(self : TerminalInfo) -> Bool {
  self.color_supported
}

///|
pub(all) enum SignalKind {
  Interrupt
  Terminate
  Hangup
  OtherSignal(Int)
} derive(Eq, Debug)

///|
/// Return the conventional Unix signal number used by just's exit-status
/// contract. Unknown native signals retain their positive numeric value.
pub fn SignalKind::number(self : SignalKind) -> Int {
  match self {
    Hangup => 1
    Interrupt => 2
    Terminate => 15
    OtherSignal(value) => Int::max(1, value)
  }
}

///|
pub fn SignalKind::exit_code(self : SignalKind) -> Int {
  128 + Int::min(self.number(), 127)
}

///|
pub fn SignalKind::name(self : SignalKind) -> String {
  match self {
    Hangup => "SIGHUP"
    Interrupt => "SIGINT"
    Terminate => "SIGTERM"
    OtherSignal(3) => "SIGQUIT"
    OtherSignal(value) => "SIG" + value.to_string()
  }
}

///|
/// How a child stream is connected to the MoonJust process.
pub(all) enum StdioBehavior {
  /// Capture the stream in the returned `ProcessResult`.
  Capture
  /// Connect the stream directly to the parent process.
  Inherit
  /// Connect the stream to the platform null device.
  Discard
} derive(Eq, Debug)

///|
/// Parent stream selected for runtime-owned output such as command echoes.
pub(all) enum OutputStream {
  Stdout
  Stderr
} derive(Eq, Debug)

///|
/// A shell-independent process request.
///
/// `Debug` is implemented manually and deliberately omits argument values,
/// environment values, and stdin bytes. Process specifications may contain
/// secrets and must never be exposed through structural diagnostics.
pub struct CommandSpec {
  program : String
  arguments : Array[String]
  mut cwd : @path.PathValue?
  environment : Array[(String, String)]
  mut inherit_environment : Bool
  mut stdin : Bytes
  mut inherit_stdin : Bool
  mut stdout : StdioBehavior
  mut stderr : StdioBehavior
} derive(Eq)

///|
pub fn CommandSpec::new(
  program : String,
  arguments : Array[String],
) -> CommandSpec raise HostError {
  if program == "" {
    raise InvalidInput("process program must not be empty")
  }
  {
    program,
    arguments: arguments[:].to_owned(),
    cwd: None,
    environment: [],
    inherit_environment: true,
    stdin: b"",
    inherit_stdin: false,
    stdout: Capture,
    stderr: Capture,
  }
}

///|
pub fn CommandSpec::program(self : CommandSpec) -> String {
  self.program
}

///|
pub fn CommandSpec::arguments(self : CommandSpec) -> ArrayView[String] {
  self.arguments[:]
}

///|
pub fn CommandSpec::cwd(self : CommandSpec) -> @path.PathValue? {
  self.cwd
}

///|
pub fn CommandSpec::environment(
  self : CommandSpec,
) -> ArrayView[(String, String)] {
  self.environment[:]
}

///|
pub fn CommandSpec::inherits_environment(self : CommandSpec) -> Bool {
  self.inherit_environment
}

///|
pub fn CommandSpec::stdin(self : CommandSpec) -> BytesView {
  self.stdin[:]
}

///|
pub fn CommandSpec::inherits_stdin(self : CommandSpec) -> Bool {
  self.inherit_stdin
}

///|
pub fn CommandSpec::stdout(self : CommandSpec) -> StdioBehavior {
  self.stdout
}

///|
pub fn CommandSpec::stderr(self : CommandSpec) -> StdioBehavior {
  self.stderr
}

///|
pub fn CommandSpec::set_cwd(self : CommandSpec, cwd : @path.PathValue) -> Unit {
  self.cwd = Some(cwd)
}

///|
pub fn CommandSpec::add_environment(
  self : CommandSpec,
  key : String,
  value : String,
) -> Unit raise HostError {
  if key == "" ||
    key.contains("=") ||
    key.contains("\u{0000}") ||
    value.contains("\u{0000}") {
    raise InvalidInput("invalid process environment entry")
  }
  for index, entry in self.environment {
    if entry.0 == key {
      self.environment[index] = (key, value)
      return
    }
  }
  self.environment.push((key, value))
}

///|
pub fn CommandSpec::set_inherit_environment(
  self : CommandSpec,
  should_inherit : Bool,
) -> Unit {
  self.inherit_environment = should_inherit
}

///|
pub fn CommandSpec::set_stdin(self : CommandSpec, stdin : Bytes) -> Unit {
  self.stdin = stdin
  self.inherit_stdin = false
}

///|
pub fn CommandSpec::set_inherit_stdin(
  self : CommandSpec,
  should_inherit : Bool,
) -> Unit {
  self.inherit_stdin = should_inherit
  if should_inherit {
    self.stdin = b""
  }
}

///|
pub fn CommandSpec::set_stdout(
  self : CommandSpec,
  behavior : StdioBehavior,
) -> Unit {
  self.stdout = behavior
}

///|
pub fn CommandSpec::set_stderr(
  self : CommandSpec,
  behavior : StdioBehavior,
) -> Unit {
  self.stderr = behavior
}

///|
/// Copy a process request so runtime stdio policy can be applied without
/// mutating the reusable execution plan.
pub fn CommandSpec::copy(self : CommandSpec) -> CommandSpec {
  {
    program: self.program,
    arguments: self.arguments.copy(),
    cwd: self.cwd,
    environment: self.environment.copy(),
    inherit_environment: self.inherit_environment,
    stdin: self.stdin,
    inherit_stdin: self.inherit_stdin,
    stdout: self.stdout,
    stderr: self.stderr,
  }
}

///|
pub impl Debug for CommandSpec with fn to_repr(self) {
  Repr::record({
    "program": Repr(self.program),
    "argument_count": Repr(self.arguments.length()),
    "cwd": Repr(self.cwd),
    "environment_keys": Repr(self.environment.map(fn(entry) { entry.0 })),
    "inherits_environment": Repr(self.inherit_environment),
    "stdin_bytes": Repr(self.stdin.length()),
    "inherits_stdin": Repr(self.inherit_stdin),
    "stdout": Repr(self.stdout),
    "stderr": Repr(self.stderr),
  })
}

///|
/// How a child process terminated.
pub(all) enum ProcessTermination {
  Exited(Int)
  Signaled(SignalKind)
  Interrupted(SignalKind)
} derive(Eq, Debug)

///|
/// Captured result of one child process.
///
/// Structural debug output reports byte counts instead of captured contents,
/// since child output may contain credentials or other sensitive values.
pub struct ProcessResult {
  termination : ProcessTermination
  stdout : Bytes
  stderr : Bytes
} derive(Eq)

///|
pub fn ProcessResult::new(
  exit_code : Int,
  stdout : Bytes,
  stderr : Bytes,
) -> ProcessResult {
  { termination: Exited(exit_code), stdout, stderr, }
}

///|
pub fn ProcessResult::from_signal(
  signal : SignalKind,
  stdout : Bytes,
  stderr : Bytes,
) -> ProcessResult {
  { termination: Signaled(signal), stdout, stderr, }
}

///|
/// Construct a result for a signal caught by the command runner while it was
/// waiting for the child. This is distinct from the child itself being killed.
pub fn ProcessResult::from_interruption(
  signal : SignalKind,
  stdout : Bytes,
  stderr : Bytes,
) -> ProcessResult {
  { termination: Interrupted(signal), stdout, stderr, }
}

///|
pub fn ProcessResult::termination(self : ProcessResult) -> ProcessTermination {
  self.termination
}

///|
pub fn ProcessResult::exit_code(self : ProcessResult) -> Int? {
  match self.termination {
    Exited(code) => Some(code)
    Signaled(_) | Interrupted(_) => None
  }
}

///|
pub fn ProcessResult::signal(self : ProcessResult) -> SignalKind? {
  match self.termination {
    Exited(_) => None
    Signaled(signal) | Interrupted(signal) => Some(signal)
  }
}

///|
pub fn ProcessResult::success(self : ProcessResult) -> Bool {
  self.termination == Exited(0)
}

///|
pub fn ProcessResult::stdout(self : ProcessResult) -> BytesView {
  self.stdout[:]
}

///|
pub fn ProcessResult::stderr(self : ProcessResult) -> BytesView {
  self.stderr[:]
}

///|
pub impl Debug for ProcessResult with fn to_repr(self) {
  Repr::record({
    "termination": Repr(self.termination),
    "stdout_bytes": Repr(self.stdout.length()),
    "stderr_bytes": Repr(self.stderr.length()),
  })
}
