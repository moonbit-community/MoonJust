///|
test "upstream value::tests::display" {
  assert_eq(Value::List([]).display(), "[]")
  assert_eq(Value::String("foo").display(), "\"foo\"")
  assert_eq(
    Value::List([String("foo"), String("bar")]).display(),
    "[\"foo\", \"bar\"]",
  )
  assert_eq(Value::String("a\tb\"c").display(), "\"a\\tb\\\"c\"")
  assert_eq(
    Value::List([String("\\"), String("\n")]).display(),
    "[\"\\\\\", \"\\n\"]",
  )
}

///|
test "upstream value::tests::from_str" {
  assert_eq(Value::String("foo bar").elements(), ["foo bar"])
  assert_eq(Value::String("foo").elements(), ["foo"])
  assert_eq(Value::List([]).elements(), [])
}

///|
test "upstream value::tests::is_truthy" {
  assert_true(!Value::List([]).truthy())
  assert_true(Value::List([String("")]).truthy())
  assert_true(Value::List([String("foo")]).truthy())
  assert_true(Value::List([String(""), String("")]).truthy())
  assert_true(Value::List([String("foo"), String("bar")]).truthy())
}

///|
test "upstream value::tests::join" {
  assert_eq(Value::List([]).join(" "), "")
  assert_eq(Value::List([String("")]).join(" "), "")
  assert_eq(Value::List([String("foo")]).join(" "), "foo")
  assert_eq(Value::List([String("foo"), String("bar")]).join(" "), "foo bar")
  assert_eq(
    Value::List([String("foo bar"), String("baz")]).join(" "),
    "foo bar baz",
  )
  assert_eq(Value::List([String(""), String("")]).join(" "), " ")
}
