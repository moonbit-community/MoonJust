///|
test "release metadata is explicit" {
  assert_eq(@MoonJust.version(), "0.6.0-alpha")
  assert_eq(@MoonJust.compatible_just_version(), "1.57.0")
  assert_eq(
    @MoonJust.version_line(),
    "moonjust 0.6.0-alpha (compatible with just 1.57.0)",
  )
}
