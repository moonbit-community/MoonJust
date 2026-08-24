///|
#cfg(all(target="native", not(platform="windows")))
#borrow(buffer)
extern "C" fn native_uname(buffer : Bytes) -> Int = "uname"

///|
#cfg(all(target="native", not(platform="windows")))
#external
priv type NativeCwdPointer

///|
#cfg(all(target="native", not(platform="windows")))
#borrow(buffer)
extern "C" fn native_getcwd(buffer : Bytes, capacity : Int) -> NativeCwdPointer = "getcwd"

///|
#cfg(all(target="native", not(platform="windows")))
#borrow(pointer)
extern "C" fn native_cwd_pointer_is_null(pointer : NativeCwdPointer) -> Int = "moonbitlang_x_fs_is_null"

///|
#cfg(all(target="native", not(platform="windows")))
let native_cwd_nonunicode_state : Ref[Bool] = Ref(false)

///|
#cfg(all(target="native", not(platform="windows")))
let native_cwd_warning_state : Ref[Bool] = Ref(false)

///|
#cfg(all(target="native", not(platform="windows")))
let native_justfile_warning_state : Ref[Bool] = Ref(false)

///|
#cfg(all(target="native", not(platform="windows")))
fn native_uname_field(buffer : Bytes, offset : Int, width : Int) -> String {
  let mut length = 0
  while length < width && buffer[offset + length] != 0 {
    length += 1
  }
  @utf8.decode(buffer[offset:offset + length]) catch {
    _ => ""
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
fn native_uname_buffer() -> Bytes? {
  let buffer = Bytes::make(2048, 0)
  if native_uname(buffer) == 0 {
    Some(buffer)
  } else {
    None
  }
}

///|
#cfg(platform="windows")
fn native_operating_system() -> Int {
  3
}

///|
#cfg(not(platform="windows"))
fn native_operating_system() -> Int {
  match native_uname_buffer() {
    Some(buffer) if native_uname_field(buffer, 0, 256) == "Darwin" => 2
    Some(buffer) if native_uname_field(buffer, 0, 256) == "Linux" => 1
    _ => 0
  }
}

///|
#cfg(platform="windows")
fn native_architecture() -> String {
  match @env.get_env_var("PROCESSOR_ARCHITECTURE") {
    Some(value) if value == "AMD64" => "x86_64"
    Some(value) if value == "ARM64" => "aarch64"
    Some(value) if value == "x86" => "x86"
    Some(value) if value == "ARM" => "arm"
    _ => "unknown"
  }
}

///|
#cfg(not(platform="windows"))
fn native_architecture() -> String {
  match native_uname_buffer() {
    Some(buffer) => {
      let system = native_uname_field(buffer, 0, 256)
      let offset = if system == "Darwin" { 1024 } else { 260 }
      match native_uname_field(buffer, offset, 256) {
        value if value == "x86_64" || value == "amd64" => "x86_64"
        value if value == "arm64" || value == "aarch64" => "aarch64"
        value if value == "i386" || value == "i686" => "x86"
        value if value == "arm" || value == "armv7l" => "arm"
        _ => "unknown"
      }
    }
    None => "unknown"
  }
}

///|
#cfg(platform="windows")
fn native_current_dir() -> String {
  @env.current_dir().unwrap_or(".")
}

///|
#cfg(not(platform="windows"))
fn native_current_dir() -> String {
  let buffer = Bytes::make(32768, 0)
  let pointer = native_getcwd(buffer, buffer.length())
  if native_cwd_pointer_is_null(pointer) != 0 {
    native_cwd_nonunicode_state.val = false
    ""
  } else {
    let mut length = 0
    while length < buffer.length() && buffer[length] != 0 {
      length += 1
    }
    let value = buffer[:length].to_owned()
    let decoded : String? = Some(@utf8.decode(value)) catch { _ => None }
    match decoded {
      Some(path) => {
        native_cwd_nonunicode_state.val = false
        path
      }
      None => {
        native_cwd_nonunicode_state.val = true
        native_warn_nonunicode_cwd(value)
        "."
      }
    }
  }
}

///|
#cfg(platform="windows")
fn native_cwd_nonunicode() -> Bool {
  false
}

///|
#cfg(not(platform="windows"))
fn native_cwd_nonunicode() -> Bool {
  native_cwd_nonunicode_state.val
}

///|
#cfg(not(platform="windows"))
fn native_warn_nonunicode_cwd(path : Bytes) -> Unit {
  if native_cwd_warning_state.val {
    return
  }
  native_cwd_warning_state.val = true
  let builder = StringBuilder()
  builder.write_string("The invocation directory path `")
  for byte in path {
    let value = byte.to_int()
    if value >= 0x20 && value <= 0x7e && value != 0x60 {
      builder.write_char(value.to_char().unwrap())
    } else {
      builder.write_char('?')
    }
  }
  builder.write_string(
    "` is not Unicode. Just is considering phasing-out support for " +
    "non-Unicode paths. If you see this warning, please leave a comment on " +
    "https://github.com/casey/just/issues/3229. Thank you!\n",
  )
  let bytes = @utf8.encode(builder.to_string())
  ignore(native_write(2, bytes, bytes.length()))
}

///|
#cfg(platform="windows")
fn native_warn_nonunicode_justfile() -> Unit {
  ()
}

///|
#cfg(not(platform="windows"))
fn native_warn_nonunicode_justfile() -> Unit {
  if native_cwd_nonunicode_state.val && !native_justfile_warning_state.val {
    native_justfile_warning_state.val = true
    let bytes = @utf8.encode(
      "The justfile path `?` is not Unicode. Just is considering phasing-out " +
      "support for non-Unicode paths. If you see this warning, please leave " +
      "a comment on https://github.com/casey/just/issues/3229. Thank you!\n",
    )
    ignore(native_write(2, bytes, bytes.length()))
  }
}

///|
#cfg(platform="windows")
extern "C" fn native_is_terminal_raw(stream : Int) -> Int = "_isatty"

///|
#cfg(not(platform="windows"))
extern "C" fn native_is_terminal_raw(stream : Int) -> Int = "isatty"

///|
#cfg(platform="windows")
extern "C" fn native_pid() -> Int = "GetCurrentProcessId"

///|
#cfg(not(platform="windows"))
extern "C" fn native_pid() -> Int = "getpid"

///|
#cfg(not(platform="windows"))
extern "C" fn native_num_cpus_sysconf(name : Int) -> Int64 = "sysconf"

///|
fn native_is_terminal(stream : Int) -> Int {
  native_is_terminal_raw(stream)
}

///|
#cfg(platform="windows")
fn native_num_cpus() -> Int {
  native_num_cpus_raw(0)
}

///|
#cfg(not(platform="windows"))
fn native_num_cpus() -> Int {
  // _SC_NPROCESSORS_ONLN is 84 on Linux and 58 on Darwin.
  let value = native_num_cpus_sysconf(
    if native_operating_system() == 2 {
      58
    } else {
      84
    },
  )
  if value > 0L && value <= 2147483647L {
    value.to_int()
  } else {
    0
  }
}

///|
#cfg(platform="windows")
extern "C" fn native_num_cpus_raw(group : UInt) -> Int = "GetActiveProcessorCount"

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
  native_architecture()
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
