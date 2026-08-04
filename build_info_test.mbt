///|
test "release metadata is explicit" {
  assert_eq(@MoonJust.version(), "0.1.0-alpha.0")
  assert_eq(@MoonJust.compatible_just_version(), "1.57.0")
  assert_eq(
    @MoonJust.version_line(),
    "moonjust 0.1.0-alpha.0 (compatible with just 1.57.0)",
  )
}
