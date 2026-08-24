///|
fn value_from_strings(values : ArrayView[String]) -> Value {
  List(values.map(fn(value) { String(value) }))
}

///|
fn assert_value_contract(
  kind : String,
  values : ArrayView[String],
  expected : String,
) -> Unit raise {
  let value = value_from_strings(values)
  match kind {
    "join" => assert_eq(value.join(" "), expected)
    "display" => assert_eq(value.display(), expected)
    _ => fail("unknown value contract")
  }
}

///|
test "contract JUST-1.57.0-2359 value::tests::display" {
  assert_value_contract("display", [], "[]")
  assert_value_contract("display", ["foo"], "\"foo\"")
  assert_value_contract("display", ["foo", "bar"], "[\"foo\", \"bar\"]")
  assert_value_contract("display", ["a\tb\"c"], "\"a\\tb\\\"c\"")
  assert_value_contract("display", ["\\", "\n"], "[\"\\\\\", \"\\n\"]")
}

///|
test "contract JUST-1.57.0-2360 value::tests::from_str" {
  assert_eq(value_from_strings(["foo bar"]).elements(), ["foo bar"])
  assert_eq(value_from_strings([]).elements(), [])
}

///|
test "contract JUST-1.57.0-2361 value::tests::is_truthy" {
  assert_eq(value_from_strings([]).truthy(), false)
  assert_eq(value_from_strings([""]).truthy(), true)
  assert_eq(value_from_strings(["foo"]).truthy(), true)
  assert_eq(value_from_strings(["", ""]).truthy(), true)
  assert_eq(value_from_strings(["foo", "bar"]).truthy(), true)
}

///|
test "contract JUST-1.57.0-2362 value::tests::join" {
  assert_value_contract("join", [], "")
  assert_value_contract("join", [""], "")
  assert_value_contract("join", ["foo"], "foo")
  assert_value_contract("join", ["foo", "bar"], "foo bar")
  assert_value_contract("join", ["foo bar", "baz"], "foo bar baz")
  assert_value_contract("join", ["", ""], " ")
}
