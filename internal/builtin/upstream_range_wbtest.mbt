///|
test "upstream range_ext::tests::display" {
  assert_eq(argument_range_description(0, Some(0)), "0")
  assert_eq(argument_range_description(1, Some(1)), "1")
  assert_eq(argument_range_description(5, Some(5)), "5")
  assert_eq(argument_range_description(5, Some(9)), "5 to 9")
  assert_eq(argument_range_description(1, None), "1 or more")
}
