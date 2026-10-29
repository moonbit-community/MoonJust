///|
test "upstream value::tests::color_display" {
  assert_eq(@value.Value::String("foo").display(), "\"foo\"")
  assert_eq(@value.Value::List([]).display(), "[]")
  assert_eq(
    @value.Value::List([String("foo"), String("bar")]).display(),
    "[\"foo\", \"bar\"]",
  )
}
