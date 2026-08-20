///|
#cfg(all(target="native", not(platform="windows")))
async test "signal status keeps the direct child result without a fixed registry" {
  assert_eq(signal_process_status(0), 0)
  assert_eq(signal_process_status(-15), -15)
}

///|
#cfg(all(target="native", not(platform="windows")))
test "process group helper validates payload without taking process ownership" {
  assert_eq(process_group_exec_ffi(b"", 0), 22)
  assert_eq(process_group_exec_ffi(b"\x00", 1), 22)
  assert_eq(
    process_group_payload(["a b", "", "c\\d"][:]),
    b"a b\x00\x00c\\d\x00",
  )
}
