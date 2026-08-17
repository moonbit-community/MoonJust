///|
test "release metadata is explicit" {
  assert_eq(@api.version(), "0.7.0-alpha.1")
  assert_eq(@api.just_compatibility_target(), "1.57.0")
  assert_eq(@api.version_line(), "moonjust 0.7.0-alpha.1")
}
