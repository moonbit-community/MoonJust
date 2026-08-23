///|
fn native_current_dir() -> String {
  ""
}

///|
fn detected_operating_system() -> @host.OperatingSystem {
  match @env.get_env_var("MOONJUST_OS") {
    Some("linux") => Linux
    Some("macos") | Some("darwin") => Macos
    Some("windows") => Windows
    Some(value) => Other(value)
    None => Other("wasm")
  }
}

///|
fn detected_architecture() -> String {
  match @env.get_env_var("MOONJUST_ARCH") {
    Some("arm64") | Some("ARM64") => "aarch64"
    Some("amd64") | Some("AMD64") => "x86_64"
    Some(value) => value
    None => "wasm32"
  }
}

///|
fn portable_positive_int(name : String) -> Int? {
  guard @env.get_env_var(name) is Some(value) else { return None }
  let parsed = @string.parse_int(value[:]) catch { _ => return None }
  if parsed > 0 {
    Some(parsed)
  } else {
    None
  }
}

///|
fn detected_pid() -> Int? {
  portable_positive_int("MOONJUST_PID")
}

///|
fn detected_num_cpus() -> Int? {
  portable_positive_int("MOONJUST_NUM_CPUS")
}

///|
fn detected_executable() -> String? {
  match @env.get_env_var("MOONJUST_EXECUTABLE") {
    Some(value) => Some(value)
    None => @env.args().get(0)
  }
}

///|
fn detected_terminal_info() -> @host.TerminalInfo {
  @host.TerminalInfo::new(false, false, false, false)
}

///|
fn detected_portable_runtime() -> Bool {
  true
}
