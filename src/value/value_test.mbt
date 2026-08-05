///|
test "values preserve typed truthiness and list rendering" {
  assert_true(Value::String("ok").truthy())
  assert_false(Value::List([]).truthy())
  assert_eq(Value::List([String("a"), String("b")]).join(","), "a,b")
  assert_eq(Value::Bool(true).to_string(), "true")
}
