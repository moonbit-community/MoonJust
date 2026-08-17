///|
test "Unicode display width handles wide combining and emoji scalars" {
  assert_eq(display_width("abc"), 3)
  assert_eq(display_width("构建"), 4)
  assert_eq(display_width("e\u{0301}"), 1)
  assert_eq(display_width("🙂"), 2)
  assert_eq(display_width("✈️"), 1)
  assert_eq(display_width("👩‍💻"), 2)
  assert_eq(display_width("🇨🇳"), 2)
  assert_eq(display_width("A\u{0007}B"), 2)
}

///|
test "query lexical sort order is ascending" {
  let values = ["z", "alpha", "joined"]
  values.sort_by(lexical_compare)
  assert_eq(values, ["alpha", "joined", "z"])
}

///|
fn format_test_list(
  values : ArrayView[String],
  conjunction : String,
  ticked : Bool,
) -> String {
  let rendered = values.map(fn(value) {
    if ticked {
      "`" + value + "`"
    } else {
      value
    }
  })
  match rendered.length() {
    0 => ""
    1 => rendered[0]
    2 => rendered[0] + " " + conjunction + " " + rendered[1]
    length =>
      rendered[:length - 1].join(", ") +
      ", " +
      conjunction +
      " " +
      rendered[length - 1]
  }
}

///|
test "human-readable lists use upstream conjunctions and ticks" {
  assert_eq(format_test_list(["1"], "or", false), "1")
  assert_eq(format_test_list(["1", "2"], "or", false), "1 or 2")
  assert_eq(format_test_list(["1", "2", "3"], "or", false), "1, 2, or 3")
  assert_eq(
    format_test_list(["1", "2", "3", "4"], "and", false),
    "1, 2, 3, and 4",
  )
  assert_eq(format_test_list(["1", "2", "3"], "or", true), "`1`, `2`, or `3`")
  assert_eq(format_test_list(["1", "2", "3"], "and", true), "`1`, `2`, and `3`")
}
