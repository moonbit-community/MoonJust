///|
test "upstream value::tests::color_display" {
  assert_eq(Value::String("foo").display(), "\"foo\"")
  assert_eq(Value::List([]).display(), "[]")
  assert_eq(
    Value::List([String("foo"), String("bar")]).display(),
    "[\"foo\", \"bar\"]",
  )
}
