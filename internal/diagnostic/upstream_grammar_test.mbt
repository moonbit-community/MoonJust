///|
test "upstream count::tests::count" {
  assert_eq(Count::numbered("dog", 0).to_string(), "0 dogs")
  assert_eq(Count::numbered("dog", 1).to_string(), "1 dog")
  assert_eq(Count::numbered("dog", 2).to_string(), "2 dogs")
  assert_eq(Count::numbered_irregular("foot", "feet", 0).to_string(), "0 feet")
  assert_eq(Count::numbered_irregular("foot", "feet", 1).to_string(), "1 foot")
  assert_eq(Count::numbered_irregular("foot", "feet", 2).to_string(), "2 feet")
  assert_eq(Count::unnumbered("dog", 0).to_string(), "dogs")
  assert_eq(Count::unnumbered("dog", 1).to_string(), "dog")
  assert_eq(Count::unnumbered("dog", 2).to_string(), "dogs")
}

///|
test "upstream enclosure::tests::tick" {
  assert_eq(tick("foo"), "`foo`")
}

///|
test "upstream list::tests::and" {
  assert_eq(join_list(["1"], "and"), "1")
  assert_eq(join_list(["1", "2"], "and"), "1 and 2")
  assert_eq(join_list(["1", "2", "3"], "and"), "1, 2, and 3")
  assert_eq(join_list(["1", "2", "3", "4"], "and"), "1, 2, 3, and 4")
}

///|
test "upstream list::tests::and_ticked" {
  assert_eq(join_list(["1"], "and", ticked=true), "`1`")
  assert_eq(join_list(["1", "2"], "and", ticked=true), "`1` and `2`")
  assert_eq(join_list(["1", "2", "3"], "and", ticked=true), "`1`, `2`, and `3`")
}

///|
test "upstream list::tests::or" {
  assert_eq(join_list(["1"], "or"), "1")
  assert_eq(join_list(["1", "2"], "or"), "1 or 2")
  assert_eq(join_list(["1", "2", "3"], "or"), "1, 2, or 3")
  assert_eq(join_list(["1", "2", "3", "4"], "or"), "1, 2, 3, or 4")
}

///|
test "upstream list::tests::or_ticked" {
  assert_eq(join_list(["1"], "or", ticked=true), "`1`")
  assert_eq(join_list(["1", "2"], "or", ticked=true), "`1` or `2`")
  assert_eq(join_list(["1", "2", "3"], "or", ticked=true), "`1`, `2`, or `3`")
}
