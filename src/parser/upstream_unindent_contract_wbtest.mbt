///|
fn assert_unindent_contract(input : String, expected : String) -> Unit raise {
  assert_eq(unindent_string(input), expected)
}

///|
fn assert_indentation_contract(input : String, expected : String) -> Unit raise {
  assert_eq(string_line_indentation(input), expected)
}

///|
fn assert_blank_contract(input : String, expected : Bool) -> Unit raise {
  assert_eq(string_line_is_blank(input), expected)
}

///|
fn assert_common_contract(
  left : String,
  right : String,
  expected : String,
) -> Unit raise {
  assert_eq(common_string_indentation(left, right), expected)
}

///|
test "contract JUST-1.57.0-2344 unindent::tests::blanks" {
  assert_blank_contract("       \n", true)
  assert_blank_contract("       foo\n", false)
  assert_blank_contract("\t\t\n", true)
}

///|
test "contract JUST-1.57.0-2345 unindent::tests::commons" {
  assert_common_contract("foo", "foobar", "foo")
  assert_common_contract("foo", "bar", "")
  assert_common_contract("", "", "")
  assert_common_contract("", "bar", "")
}

///|
test "contract JUST-1.57.0-2346 unindent::tests::indentations" {
  assert_indentation_contract("", "")
  assert_indentation_contract("foo", "")
  assert_indentation_contract("   foo", "   ")
  assert_indentation_contract("\t\tfoo", "\t\t")
  assert_indentation_contract("\t \t foo", "\t \t ")
}

///|
test "contract JUST-1.57.0-2347 unindent::tests::unindents" {
  assert_unindent_contract("foo", "foo")
  assert_unindent_contract("foo\nbar\nbaz\n", "foo\nbar\nbaz\n")
  assert_unindent_contract("", "")
  assert_unindent_contract("  foo\n  bar", "foo\nbar")
  assert_unindent_contract("  foo\n  bar\n\n", "foo\nbar\n")
  assert_unindent_contract("  foo\r\n\r\n  bar\r\n", "foo\r\n\r\nbar\r\n")
  assert_unindent_contract(
    "\n          hello\n          bar\n        ", "hello\nbar\n",
  )
  assert_unindent_contract("hello\n  bar\n  foo", "hello\n  bar\n  foo")
  assert_unindent_contract(
    "\n\n          hello\n          bar\n\n        ", "\nhello\nbar\n\n",
  )
}
