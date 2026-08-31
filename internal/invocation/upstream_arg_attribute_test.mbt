///|
fn arg_attribute_compilation(text : String) -> @semantic.Compilation raise {
  @semantic.compile_source(
    @source.Source::from_text(@source.SourceId::new(900), "justfile", text),
    allow_unstable=true,
  )
}

///|
fn invalid_count_value(value : String, key : String) -> Bool {
  let source = "[arg('bar', " + key + "='" + value + "')]\nfoo +bar:\n"
  let compilation = try! arg_attribute_compilation(source)
  try parse_invocations(compilation, ["foo"]) catch {
    InvalidArgumentAttribute(detail~, ..) =>
      detail == "invalid `" + key + "` value `" + value + "`"
    _ => false
  } noraise {
    _ => false
  }
}

///|
test "upstream arg_attribute::invalid_max_value_error" {
  assert_true(invalid_count_value("x", "max"))
  assert_true(invalid_count_value("+1", "max"))
  assert_true(invalid_count_value("01", "max"))
  assert_true(invalid_count_value("1 ", "max"))
}

///|
test "upstream arg_attribute::invalid_min_value_error" {
  assert_true(invalid_count_value("x", "min"))
  assert_true(invalid_count_value("+1", "min"))
  assert_true(invalid_count_value("01", "min"))
  assert_true(invalid_count_value("1 ", "min"))
}

///|
test "upstream arg_attribute::patterns_are_regular_expressions" {
  let compilation = try! arg_attribute_compilation(
    "[arg('bar', pattern='\\d+')]\nfoo bar:\n",
  )
  try parse_invocations(compilation, ["foo", "\\d+"]) catch {
    ArgumentPatternMismatch(
      recipe="foo",
      parameter="bar",
      argument="\\d+",
      patterns=["\\d+"]
    ) => ()
    error => fail("unexpected invocation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected argument pattern error")
  }
}
