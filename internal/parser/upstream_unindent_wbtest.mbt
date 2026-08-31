///|
test "upstream unindent::tests::blanks" {
  assert_eq(string_line_is_blank("       \n"), true)
  assert_eq(string_line_is_blank("       foo\n"), false)
  assert_eq(string_line_is_blank("\t\t\n"), true)
}

///|
test "upstream unindent::tests::commons" {
  assert_eq(common_string_indentation("foo", "foobar"), "foo")
  assert_eq(common_string_indentation("foo", "bar"), "")
  assert_eq(common_string_indentation("", ""), "")
  assert_eq(common_string_indentation("", "bar"), "")
}

///|
test "upstream unindent::tests::indentations" {
  assert_eq(string_line_indentation(""), "")
  assert_eq(string_line_indentation("foo"), "")
  assert_eq(string_line_indentation("   foo"), "   ")
  assert_eq(string_line_indentation("\t\tfoo"), "\t\t")
  assert_eq(string_line_indentation("\t \t foo"), "\t \t ")
}
