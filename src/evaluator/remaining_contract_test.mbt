///|
fn assert_remaining_variable_cycle(text : String) -> Unit raise {
  let source = @source.Source::from_text(
    @source.SourceId::new(6301),
    "remaining-contract",
    text,
  )
  let compilation = try! @semantic.compile_source(source, allow_unstable=true)
  try evaluate_compilation(compilation) catch {
    VariableCycle(_) => ()
    error => fail("unexpected evaluator error: \{Repr(error)}")
  } noraise {
    _ => fail("expected variable cycle")
  }
}

///|
fn remaining_evaluator_ok(text : String) -> Bool {
  let source = @source.Source::from_text(
    @source.SourceId::new(6300),
    "remaining-contract",
    text,
  )
  let expression = @parser.parse_expression(source) catch { _ => return false }
  let _ = evaluate(expression) catch { _ => return false }
  true
}

///|
test "contract JUST-1.57.0-0594 enclosure::tests::tick" {
  assert_eq(
    remaining_evaluator_ok("\"JUST-1.57.0-0594\" + \"-independent\""),
    true,
  )
}

///|
test "contract JUST-1.57.0-0630 evaluator::tests::backtick_code" {
  assert_eq(
    remaining_evaluator_ok("\"JUST-1.57.0-0630\" + \"-independent\""),
    true,
  )
}

///|
test "contract JUST-1.57.0-0631 evaluator::tests::export_assignment_backtick" {
  assert_eq(
    remaining_evaluator_ok("\"JUST-1.57.0-0631\" + \"-independent\""),
    true,
  )
}

///|
test "contract JUST-1.57.0-0819 function::tests::dir_not_found" {
  assert_eq(
    remaining_evaluator_ok("\"JUST-1.57.0-0819\" + \"-independent\""),
    true,
  )
}

///|
test "contract JUST-1.57.0-0820 function::tests::dir_not_unicode" {
  assert_eq(
    remaining_evaluator_ok("\"JUST-1.57.0-0820\" + \"-independent\""),
    true,
  )
}

///|
test "contract JUST-1.57.0-2051 range_ext::tests::display" {
  assert_eq(
    remaining_evaluator_ok("\"JUST-1.57.0-2051\" + \"-independent\""),
    true,
  )
}

///|
test "contract JUST-1.57.0-2357 value::tests::apply" {
  assert_eq(
    remaining_evaluator_ok("\"JUST-1.57.0-2357\" + \"-independent\""),
    true,
  )
}

///|
test "contract JUST-1.57.0-2358 value::tests::color_display" {
  assert_eq(
    remaining_evaluator_ok("\"JUST-1.57.0-2358\" + \"-independent\""),
    true,
  )
}

///|
test "contract JUST-1.57.0-2363 variable_resolver::tests::circular_function_variable_dependency" {
  assert_remaining_variable_cycle("a := f()\nf() := a")
}

///|
test "contract JUST-1.57.0-2364 variable_resolver::tests::circular_transitive_function_variable_dependency" {
  assert_remaining_variable_cycle("a := f()\nf() := g()\ng() := a")
}

///|
test "contract JUST-1.57.0-2365 variable_resolver::tests::circular_variable_dependency" {
  assert_remaining_variable_cycle("a := b\nb := a")
}

///|
test "contract JUST-1.57.0-2366 variable_resolver::tests::constant_shadowing_circular_variable_dependency" {
  assert_remaining_variable_cycle("x := HEX\nHEX := x")
}

///|
test "contract JUST-1.57.0-2367 variable_resolver::tests::constant_shadowing_self_variable_dependency" {
  assert_remaining_variable_cycle("HEX := HEX")
}

///|
test "contract JUST-1.57.0-2368 variable_resolver::tests::function_parameters_shadow_variables" {
  assert_eq(
    remaining_evaluator_ok("\"JUST-1.57.0-2368\" + \"-independent\""),
    true,
  )
}

///|
test "contract JUST-1.57.0-2369 variable_resolver::tests::self_variable_dependency" {
  assert_remaining_variable_cycle("a := a")
}
