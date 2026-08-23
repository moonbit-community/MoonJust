///|
test "values preserve typed truthiness and list rendering" {
  assert_true(Value::String("ok").truthy())
  assert_true(Value::String("").truthy())
  assert_false(Value::List([]).truthy())
  assert_eq(Value::List([String("a"), String("b")]).join(","), "a,b")
  assert_eq(Value::Bool(true).to_string(), "true")
  assert_eq(Value::Bool(false).to_string(), "")
  assert_eq(Value::List([String("a"), String("b")]).to_string(), "a b")
  assert_eq(Value::String("a\nb").display(), "\"a\\nb\"")
  assert_eq(Value::Bool(false).display(), "[]")
}

///|
test "value accessors and rendering cover every variant" {
  assert_eq(Value::String("text").as_string(), Some("text"))
  assert_eq(Value::List([String("only")]).as_string(), Some("only"))
  assert_eq(Value::List([Bool(true)]).as_string(), Some("true"))
  assert_eq(Value::List([String("a"), String("b")]).as_string(), None)
  assert_eq(Value::Bool(false).as_string(), None)
  assert_eq(Value::Bool(true).as_string(), Some("true"))
  let single : Array[Value] = [String("a")]
  assert_eq(Value::List(single).as_list(), Some(single[:]))
  assert_eq(Value::String("a").as_list(), None)
  assert_eq(Value::Bool(true).as_bool(), Some(true))
  assert_eq(Value::List([]).as_bool(), None)
  assert_eq(Value::String("a").kind(), "string")
  assert_eq(Value::List([]).kind(), "list")
  assert_eq(Value::Bool(true).kind(), "boolean")
  assert_eq(
    Value::List([String("a"), Bool(true), List([String("b")])]).elements(),
    ["a", "true", "b"],
  )
  assert_eq(Value::String("\\\"\t\r\n").display(), "\"\\\\\\\"\\t\\r\\n\"")
  assert_eq(Value::List([String("a"), String("b")]).display(), "[\"a\", \"b\"]")
  try Value::String("a").join(",") catch {
    TypeMismatch(expected="list", actual="string") => ()
    error => fail("unexpected join error: \{Repr(error)}")
  } noraise {
    _ => fail("expected scalar join to fail")
  }
}
