///|
fn runtime_host() -> @host_native.NativeFs {
  ignore(@host_wasm.ReadOnlyFs::new)
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
