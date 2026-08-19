///|
extern "C" fn native_operating_system() -> Int = "moonjust_host_operating_system"

///|
extern "C" fn native_architecture() -> Int = "moonjust_host_architecture"

///|
#borrow(path)
extern "C" fn native_short_path(path : String) -> String = "moonjust_host_short_path"

///|
extern "C" fn native_is_terminal(stream : Int) -> Int = "moonjust_host_is_terminal"

///|
extern "C" fn native_pid() -> Int = "moonjust_host_pid"

///|
extern "C" fn native_num_cpus() -> Int = "moonjust_host_num_cpus"

///|
fn detected_pid() -> Int? {
  match native_pid() {
    value if value > 0 => Some(value)
    _ => None
  }
}

///|
fn detected_num_cpus() -> Int? {
  match native_num_cpus() {
    value if value > 0 => Some(value)
    _ => None
  }
}

///|
fn detected_executable() -> String? {
  @env.args().get(0)
}

///|
fn detected_operating_system() -> @host.OperatingSystem {
  match native_operating_system() {
    1 => Linux
    2 => Macos
    3 => Windows
    _ => Other("native")
  }
}

///|
fn detected_architecture() -> String {
  match native_architecture() {
    1 => "x86_64"
    2 => "aarch64"
    3 => "x86"
    4 => "arm"
    _ => "unknown"
  }
}

///|
fn detected_terminal_info() -> @host.TerminalInfo {
  let stdin_is_terminal = native_is_terminal(0) != 0
  let stdout_is_terminal = native_is_terminal(1) != 0
  let stderr_is_terminal = native_is_terminal(2) != 0
  let term = @env.get_env_var("TERM")
  let color_supported = @env.get_env_var("NO_COLOR") is None &&
    term != Some("dumb")
  @host.TerminalInfo::new(
    stdin_is_terminal, stdout_is_terminal, stderr_is_terminal, color_supported,
  )
}

///|
fn detected_portable_runtime() -> Bool {
  false
}
