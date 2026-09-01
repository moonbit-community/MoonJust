///|
test "upstream unindent::tests::unindents" {
  assert_eq(unindent_string("foo"), "foo")
  assert_eq(unindent_string("foo\nbar\nbaz\n"), "foo\nbar\nbaz\n")
  assert_eq(unindent_string(""), "")
  assert_eq(unindent_string("  foo\n  bar"), "foo\nbar")
  assert_eq(unindent_string("  foo\n  bar\n\n"), "foo\nbar\n")
  assert_eq(unindent_string("  foo\r\n\r\n  bar\r\n"), "foo\r\n\r\nbar\r\n")
  assert_eq(
    unindent_string("\n          hello\n          bar\n        "),
    "hello\nbar\n",
  )
  assert_eq(unindent_string("hello\n  bar\n  foo"), "hello\n  bar\n  foo")
  assert_eq(
    unindent_string("\n\n          hello\n          bar\n\n        "),
    "\nhello\nbar\n\n",
  )
}
