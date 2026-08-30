///|
test "upstream value::tests::display" {
  assert_eq(Value::List([]).display(), "[]")
  assert_eq(Value::String("foo").display(), "\"foo\"")
  assert_eq(
    Value::List([Value::String("foo"), Value::String("bar")]).display(),
    "[\"foo\", \"bar\"]",
  )
  assert_eq(Value::String("a\tb\"c").display(), "\"a\\tb\\\"c\"")
  assert_eq(
    Value::List([Value::String("\\"), Value::String("\n")]).display(),
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
  assert_true(Value::List([Value::String("")]).truthy())
  assert_true(Value::List([Value::String("foo")]).truthy())
  assert_true(Value::List([Value::String(""), Value::String("")]).truthy())
  assert_true(
    Value::List([Value::String("foo"), Value::String("bar")]).truthy(),
  )
}

///|
test "upstream value::tests::join" {
  assert_eq(Value::List([]).join(" "), "")
  assert_eq(Value::List([Value::String("")]).join(" "), "")
  assert_eq(Value::List([Value::String("foo")]).join(" "), "foo")
  assert_eq(
    Value::List([Value::String("foo"), Value::String("bar")]).join(" "),
    "foo bar",
  )
  assert_eq(
    Value::List([Value::String("foo bar"), Value::String("baz")]).join(" "),
    "foo bar baz",
  )
  assert_eq(Value::List([Value::String(""), Value::String("")]).join(" "), " ")
}
