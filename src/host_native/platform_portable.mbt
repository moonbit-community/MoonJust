///|
fn detected_operating_system() -> @host.OperatingSystem {
  Other("wasm")
}

///|
fn detected_architecture() -> String {
  "wasm32"
}

///|
fn detected_terminal_info() -> @host.TerminalInfo {
  @host.TerminalInfo::new(false, false, false, false)
}
