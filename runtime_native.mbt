///|
fn runtime_host() -> @host_native.NativeFs {
  @host_native.NativeFs::new()
}

///|
fn runtime_environment_host() -> @host_native.NativeFs {
  @host_native.NativeFs::new()
}

///|
#cfg(platform="windows")
extern "C" fn native_set_file_mode(fd : Int, mode : Int) -> Int = "_setmode"

///|
#cfg(platform="windows")
fn configure_binary_standard_streams() -> Unit {
  // Keep CLI output byte-stable. The Windows CRT otherwise expands LF to CRLF.
  ignore(native_set_file_mode(1, 0x8000))
  ignore(native_set_file_mode(2, 0x8000))
}

///|
extern "c" fn native_exit(code : Int) = "exit"

///|
fn runtime_exit(code : Int) -> Unit {
  if code != 0 {
    native_exit(code)
  }
}

///|
/// Native commands already use the direct host implementation.
#cfg(target="native")
fn try_runtime_fast_path(_argv : ArrayView[String]) -> ImmediateResult {
  NotHandled
}
