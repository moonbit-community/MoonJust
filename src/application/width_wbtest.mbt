///|
test "Unicode display width handles wide combining and emoji scalars" {
  assert_eq(display_width("abc"), 3)
  assert_eq(display_width("构建"), 4)
  assert_eq(display_width("e\u{0301}"), 1)
  assert_eq(display_width("🙂"), 2)
}

///|
test "query lexical sort order is ascending" {
  let values = ["z", "alpha", "joined"]
  values.sort_by(lexical_compare)
  assert_eq(values, ["alpha", "joined", "z"])
}
