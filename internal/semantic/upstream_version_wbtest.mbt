///|
test "upstream version::tests::parse" {
  assert_eq(version_parts("0.0.0"), Some((0, 0, 0)))
  assert_true(version_parts("01.2.3") is None)
  assert_eq(version_parts("1.2.3"), Some((1, 2, 3)))
  assert_true(version_parts("1234567890.0.0") is None)
  assert_eq(version_parts("999999999.0.0"), Some((999999999, 0, 0)))
  assert_true(version_parts("foo") is None)
}

///|
test "upstream version::tests::compare" {
  fn compare(left : String, right : String) -> Int {
    let a = version_parts(left).unwrap()
    let b = version_parts(right).unwrap()
    if a == b {
      0
    } else if version_greater(a, b) {
      1
    } else {
      -1
    }
  }
  assert_eq(compare("1.2.3", "1.2.3"), 0)
  assert_eq(compare("1.2.3", "1.2.4"), -1)
  assert_eq(compare("1.3.0", "1.2.9"), 1)
  assert_eq(compare("2.0.0", "1.99.99"), 1)
}
