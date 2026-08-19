///|
#cfg(all(target="native", not(platform="windows")))
async test "signal status keeps the direct child result without a fixed registry" {
  assert_eq(signal_process_status(0), 0)
  assert_eq(signal_process_status(-15), -15)
}
