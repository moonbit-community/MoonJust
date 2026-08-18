///|
#cfg(not(platform="windows"))
test "signal child registry reports capacity without aborting" {
  for index in 0..<1024 {
    assert_eq(register_signal_child_ffi(-index - 1), 1)
  }
  assert_eq(register_signal_child_ffi(-2048), 0)
  for index in 0..<1024 {
    assert_eq(unregister_signal_child_ffi(-index - 1), 0)
  }
}
