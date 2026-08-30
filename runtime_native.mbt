///|
fn runtime_host() -> @host_native.NativeFs {
  ignore(@host_wasm.ReadOnlyFs::new)
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
/// Native has no synchronous file fast path; all native commands already use
/// the direct host implementation.
#cfg(target="native")
fn try_sync_file_command(
  _argv : ArrayView[String],
  _expected : @cli.CommandKind,
) -> Bool {
  false
}

///|
#cfg(target="native")
fn try_sync_summary(_argv : ArrayView[String]) -> String? {
  None
}

///|
#cfg(target="native")
fn sync_file_command_hint(argv : ArrayView[String]) -> Int {
  let mut check = false
  let mut format = false
  for argument in argv {
    if argument == "--summary" {
      return 1
    }
    if argument == "--check" {
      check = true
    } else if argument == "--fmt" {
      format = true
    }
  }
  if check {
    2
  } else if format {
    3
  } else {
    0
  }
}
