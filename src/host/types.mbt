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
} derive(Eq, Debug)

///|
pub fn FileMetadata::new(
  is_file : Bool,
  is_directory : Bool,
  size : Int64,
) -> FileMetadata {
  { is_file, is_directory, size }
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
} derive(Eq, Debug)

///|
pub fn PlatformInfo::new(
  operating_system : OperatingSystem,
  architecture : String,
  path_flavor : @path.PathFlavor,
) -> PlatformInfo {
  { operating_system, architecture, path_flavor }
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
  { stdin_is_terminal, stdout_is_terminal, stderr_is_terminal, color_supported }
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
/// A shell-independent process request.
pub struct CommandSpec {
  program : String
  arguments : Array[String]
  mut cwd : @path.PathValue?
  environment : Array[(String, String)]
  mut stdin : Bytes
} derive(Eq, Debug)

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
    stdin: b"",
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
pub fn CommandSpec::stdin(self : CommandSpec) -> BytesView {
  self.stdin[:]
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
  self.environment.push((key, value))
}

///|
pub fn CommandSpec::set_stdin(self : CommandSpec, stdin : Bytes) -> Unit {
  self.stdin = stdin
}

///|
/// Captured result of one child process.
pub struct ProcessOutput {
  exit_code : Int
  stdout : Bytes
  stderr : Bytes
} derive(Eq, Debug)

///|
pub fn ProcessOutput::new(
  exit_code : Int,
  stdout : Bytes,
  stderr : Bytes,
) -> ProcessOutput {
  { exit_code, stdout, stderr }
}

///|
pub fn ProcessOutput::exit_code(self : ProcessOutput) -> Int {
  self.exit_code
}

///|
pub fn ProcessOutput::stdout(self : ProcessOutput) -> BytesView {
  self.stdout[:]
}

///|
pub fn ProcessOutput::stderr(self : ProcessOutput) -> BytesView {
  self.stderr[:]
}
