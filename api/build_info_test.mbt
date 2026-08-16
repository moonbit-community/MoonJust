///|
test "release metadata is explicit" {
  assert_eq(@api.version(), "0.7.0-alpha.1")
  assert_eq(@api.compatible_just_version(), "1.57.0")
  assert_eq(
    @api.version_line(),
    "moonjust 0.7.0-alpha.1 (compatible with just 1.57.0 Tier A)",
  )
}
