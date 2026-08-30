///|
fn eval_upstream_comparison(text : String) -> Bool raise EvaluationError {
  let source = @source.Source::from_text(
    @source.SourceId::new(700),
    "expr",
    text,
  )
  evaluate_source(source).truthy()
}

///|
test "upstream comparison::and_short_circuits_on_false_comparison" {
  assert_eq(
    try! eval_upstream_comparison("\"foo\" == \"bar\" && \"baz\" == \"baz\""),
    false,
  )
}

///|
test "upstream comparison::combined_with_and" {
  assert_eq(
    try! eval_upstream_comparison("\"foo\" == \"foo\" && \"bar\" == \"bar\""),
    true,
  )
}

///|
test "upstream comparison::empty_list_does_not_equal_empty_string" {
  assert_eq(try! eval_upstream_comparison("[] == \"\""), false)
}

///|
test "upstream comparison::equality_distinguishes_element_boundaries" {
  assert_eq(
    try! eval_upstream_comparison("[\"foo\", \"bar\"] == [\"foo bar\"]"),
    false,
  )
}

///|
test "upstream comparison::equality_false" {
  assert_eq(try! eval_upstream_comparison("\"foo\" == \"bar\""), false)
}

///|
test "upstream comparison::equality_true" {
  assert_eq(try! eval_upstream_comparison("\"foo\" == \"foo\""), true)
}

///|
test "upstream comparison::inequality_distinguishes_element_boundaries" {
  assert_eq(
    try! eval_upstream_comparison("[\"foo\", \"bar\"] != [\"foo bar\"]"),
    true,
  )
}

///|
test "upstream comparison::inequality_false" {
  assert_eq(try! eval_upstream_comparison("\"foo\" != \"foo\""), false)
}

///|
test "upstream comparison::inequality_true" {
  assert_eq(try! eval_upstream_comparison("\"foo\" != \"bar\""), true)
}

///|
test "upstream comparison::list_equality_is_structural" {
  assert_eq(
    try! eval_upstream_comparison("[\"foo\", \"bar\"] == [\"foo\", \"bar\"]"),
    true,
  )
}

///|
test "upstream comparison::or_falls_through_false_comparison" {
  assert_eq(
    try! eval_upstream_comparison("\"foo\" == \"bar\" || \"baz\" == \"baz\""),
    true,
  )
}

///|
test "upstream comparison::regex_match" {
  assert_eq(try! eval_upstream_comparison("\"foo\" =~ \"f.\""), true)
}

///|
test "upstream comparison::regex_match_both_operands_lists" {
  assert_eq(
    try! eval_upstream_comparison("[\"foo\", \"bar\"] =~ [\"z\", \"b.\"]"),
    true,
  )
}

///|
test "upstream comparison::regex_match_is_false_if_no_element_matches" {
  assert_eq(try! eval_upstream_comparison("[\"foo\", \"bar\"] =~ \"z\""), false)
}

///|
test "upstream comparison::regex_match_is_true_if_any_element_matches" {
  assert_eq(try! eval_upstream_comparison("[\"foo\", \"bar\"] =~ \"b.\""), true)
}

///|
test "upstream comparison::regex_match_of_empty_list_is_false" {
  assert_eq(try! eval_upstream_comparison("[] =~ \".\""), false)
}

///|
test "upstream comparison::regex_match_with_empty_pattern_list_is_false" {
  assert_eq(try! eval_upstream_comparison("\"foo\" =~ []"), false)
}

///|
test "upstream comparison::regex_match_with_list_is_false_if_no_pattern_matches" {
  assert_eq(try! eval_upstream_comparison("\"foo\" =~ [\"x\", \"y\"]"), false)
}

///|
test "upstream comparison::regex_match_with_list_is_true_if_any_pattern_matches" {
  assert_eq(try! eval_upstream_comparison("\"foo\" =~ [\"x\", \"f.\"]"), true)
}

///|
test "upstream comparison::regex_mismatch" {
  assert_eq(try! eval_upstream_comparison("\"foo\" !~ \"b.\""), true)
}

///|
test "upstream comparison::regex_mismatch_is_false_if_any_element_matches" {
  assert_eq(
    try! eval_upstream_comparison("[\"foo\", \"bar\"] !~ \"b.\""),
    false,
  )
}

///|
test "upstream comparison::regex_mismatch_is_true_if_no_element_matches" {
  assert_eq(try! eval_upstream_comparison("[\"foo\", \"bar\"] !~ \"z\""), true)
}

///|
test "upstream comparison::regex_mismatch_of_empty_list_is_true" {
  assert_eq(try! eval_upstream_comparison("[] !~ \".\""), true)
}

///|
test "upstream comparison::regex_mismatch_with_empty_pattern_list_is_true" {
  assert_eq(try! eval_upstream_comparison("\"foo\" !~ []"), true)
}

///|
test "upstream comparison::regex_mismatch_with_list_is_false_if_any_pattern_matches" {
  assert_eq(try! eval_upstream_comparison("\"foo\" !~ [\"x\", \"f.\"]"), false)
}

///|
test "upstream comparison::regex_mismatch_with_list_is_true_if_no_pattern_matches" {
  assert_eq(try! eval_upstream_comparison("\"foo\" !~ [\"x\", \"y\"]"), true)
}
