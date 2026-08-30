///|
fn runtime_host() -> @host_native.NativeFs {
  @host_native.NativeFs::new()
}

///|
fn runtime_environment_host() -> @host_native.NativeFs {
  @host_native.NativeFs::new()
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
