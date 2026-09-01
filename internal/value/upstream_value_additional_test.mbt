///|
test "upstream value::tests::color_display" {
  assert_eq(Value::String("foo").display(), "\"foo\"")
  assert_eq(Value::List([]).display(), "[]")
  assert_eq(
    Value::List([Value::String("foo"), Value::String("bar")]).display(),
    "[\"foo\", \"bar\"]",
  )
}
