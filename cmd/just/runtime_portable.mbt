///|
fn runtime_host() -> @host_wasm.ExecutionFs {
  @host_wasm.ExecutionFs::new()
}

///|
fn runtime_environment_host() -> @host_wasm.PortableHost {
  @host_wasm.PortableHost::new()
}

///|
#cfg(target="wasm")
fn portable_exit(code : Int) -> Unit = "wasi_snapshot_preview1" "proc_exit"

///|
#cfg(any(target="wasm-gc", target="js"))
fn portable_exit(code : Int) -> Unit = "__moonbit_sys_unstable" "exit"

///|
fn runtime_exit(code : Int) -> Unit {
  if code != 0 {
    portable_exit(code)
  }
}
