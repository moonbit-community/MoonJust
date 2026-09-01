///|
fn assert_upstream_variable_cycle(
  text : String,
  expected_name : String,
  expected_stack : Array[String],
  expected_offset : Int,
  expected_width : Int,
) -> Unit raise {
  let compilation = try! @semantic.compile_source(
    @source.Source::from_text(@source.SourceId::new(960), "justfile", text),
    allow_unstable=true,
  )
  try evaluate_compilation(compilation) catch {
    VariableCycle(name~, stack~, span~) => {
      assert_eq(stack, expected_stack)
      assert_eq(name, expected_name)
      assert_eq(span.start_byte(), expected_offset)
      assert_eq(span.length(), expected_width)
    }
    error => fail("unexpected evaluator error: \{Repr(error)}")
  } noraise {
    _ => fail("expected variable cycle")
  }
}

///|
test "upstream variable_resolver::tests::circular_function_variable_dependency" {
  assert_upstream_variable_cycle("a := f()\nf() := a", "a", ["a", "a"], 0, 1)
}

///|
test "upstream variable_resolver::tests::circular_transitive_function_variable_dependency" {
  assert_upstream_variable_cycle(
    "a := f()\nf() := g()\ng() := a",
    "a",
    ["a", "a"],
    0,
    1,
  )
}

///|
test "upstream variable_resolver::tests::circular_variable_dependency" {
  assert_upstream_variable_cycle("a := b\nb := a", "a", ["a", "b", "a"], 0, 1)
}

///|
test "upstream variable_resolver::tests::constant_shadowing_circular_variable_dependency" {
  assert_upstream_variable_cycle(
    "x := HEX\nHEX := x",
    "HEX",
    ["HEX", "x", "HEX"],
    9,
    3,
  )
}

///|
test "upstream variable_resolver::tests::constant_shadowing_self_variable_dependency" {
  assert_upstream_variable_cycle("HEX := HEX", "HEX", ["HEX", "HEX"], 0, 3)
}

///|
test "upstream variable_resolver::tests::self_variable_dependency" {
  assert_upstream_variable_cycle("a := a", "a", ["a", "a"], 0, 1)
}
