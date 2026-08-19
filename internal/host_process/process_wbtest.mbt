///|
#cfg(not(platform="windows"))
async test "full signal registry reaps the rejected managed process" {
  for index in 0..<1024 {
    assert_eq(register_signal_child_ffi(-index - 1), 1)
  }
  assert_eq(register_signal_child_ffi(-2048), 0)
  defer (for index in 0..<1024 {
    ignore(unregister_signal_child_ffi(-index - 1))
  })
  let command = try! @host.CommandSpec::new("/bin/sh", ["-c", "sleep 10"])
  let rejected = try {
    ignore(
      @host.HostAsyncProcess::run_process_async(ProcessAdapter::new(), command),
    )
    false
  } catch {
    InvalidInput(message) =>
      message.contains(
        "too many concurrent child processes for signal forwarding",
      )
    error =>
      match error {
        InvalidInput(_) => false
        _ => false
      }
  } noraise {
    value => value
  }
  assert_true(rejected)
}
