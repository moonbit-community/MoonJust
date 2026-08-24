///|
test "path flavor follows the runtime operating system" {
  assert_eq(path_flavor_for_operating_system(Windows), Windows)
  assert_eq(path_flavor_for_operating_system(Linux), Unix)
  assert_eq(path_flavor_for_operating_system(Macos), Unix)
  assert_eq(path_flavor_for_operating_system(Other("wasm")), Unix)
}
