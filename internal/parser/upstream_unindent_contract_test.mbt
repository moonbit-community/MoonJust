///|
fn assert_unindent_contract(input : String, expected : String) -> Unit raise {
  assert_eq(unindent_string(input), expected)
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
