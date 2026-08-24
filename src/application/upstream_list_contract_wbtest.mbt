///|
fn assert_list_contract(
  values : ArrayView[String],
  conjunction : String,
  ticked : Bool,
  expected : String,
) -> Unit raise {
  assert_eq(format_test_list(values, conjunction, ticked), expected)
}

///|
test "contract JUST-1.57.0-1278 list::tests::and" {
  assert_list_contract(["1"], "and", false, "1")
  assert_list_contract(["1", "2"], "and", false, "1 and 2")
  assert_list_contract(["1", "2", "3"], "and", false, "1, 2, and 3")
  assert_list_contract(["1", "2", "3", "4"], "and", false, "1, 2, 3, and 4")
}

///|
test "contract JUST-1.57.0-1279 list::tests::and_ticked" {
  assert_list_contract(["1"], "and", true, "`1`")
  assert_list_contract(["1", "2"], "and", true, "`1` and `2`")
  assert_list_contract(["1", "2", "3"], "and", true, "`1`, `2`, and `3`")
  assert_list_contract(
    ["1", "2", "3", "4"],
    "and",
    true,
    "`1`, `2`, `3`, and `4`",
  )
}

///|
test "contract JUST-1.57.0-1280 list::tests::or" {
  assert_list_contract(["1"], "or", false, "1")
  assert_list_contract(["1", "2"], "or", false, "1 or 2")
  assert_list_contract(["1", "2", "3"], "or", false, "1, 2, or 3")
  assert_list_contract(["1", "2", "3", "4"], "or", false, "1, 2, 3, or 4")
}

///|
test "contract JUST-1.57.0-1281 list::tests::or_ticked" {
  assert_list_contract(["1"], "or", true, "`1`")
  assert_list_contract(["1", "2"], "or", true, "`1` or `2`")
  assert_list_contract(["1", "2", "3"], "or", true, "`1`, `2`, or `3`")
  assert_list_contract(
    ["1", "2", "3", "4"],
    "or",
    true,
    "`1`, `2`, `3`, or `4`",
  )
}
