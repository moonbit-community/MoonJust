///|
test "upstream value::tests::apply" {
  let cases = [
    ("[] + []", "[]"),
    ("['a'] + ['b']", "\"ab\""),
    ("['a'] / ['b']", "\"a/b\""),
    ("['a', 'b'] + ['c', 'd']", "[\"ac\", \"bd\"]"),
    ("['a', 'b'] / ['c', 'd']", "[\"a/c\", \"b/d\"]"),
    ("['a'] + ['b', 'c']", "[\"ab\", \"ac\"]"),
    ("['a'] + ['b', 'c', 'd']", "[\"ab\", \"ac\", \"ad\"]"),
    ("['a', 'b'] / ['c']", "[\"a/c\", \"b/c\"]"),
    ("['a', 'b', 'c'] + ['d']", "[\"ad\", \"bd\", \"cd\"]"),
  ]
  for pair in cases {
    assert_eq(try! eval_upstream_list_context(pair.0), pair.1)
  }
  for
    expression in [
      "[] + ['a']", "['a'] + []", "[] + ['a', 'b']", "['a', 'b'] + []", "['a', 'b'] + ['c', 'd', 'e']",
    ] {
    try eval_upstream_list_context(expression) catch {
      Builtin(Failure(message~), ..) =>
        assert_true(message.contains("cannot be applied"))
      error => fail("unexpected value error: \{Repr(error)}")
    } noraise {
      _ => fail("expected incompatible list error")
    }
  }
}
