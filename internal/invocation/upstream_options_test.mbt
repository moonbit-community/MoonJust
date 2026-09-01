///|
fn options_upstream_compilation(text : String) -> @semantic.Compilation raise {
  @semantic.compile_source(
    @source.Source::from_text(@source.SourceId::new(898), "justfile", text),
    allow_unstable=true,
  )
}

///|
test "upstream options::parameters_with_both_long_and_short_option_may_be_passed_as_long" {
  let compilation = try! options_upstream_compilation(
    "[arg('bar', long='bar', short='b')]\nfoo bar:\n",
  )
  let invocations = try! parse_invocations(compilation, ["foo", "--bar", "baz"])
  assert_eq(invocations.length(), 1)
  assert_eq(invocations[0].arguments()[0].elements(), ["baz"])
}

///|
test "upstream options::parameters_with_both_long_and_short_option_may_be_passed_as_short" {
  let compilation = try! options_upstream_compilation(
    "[arg('bar', long='bar', short='b')]\nfoo bar:\n",
  )
  let invocations = try! parse_invocations(compilation, ["foo", "-b", "baz"])
  assert_eq(invocations.length(), 1)
  assert_eq(invocations[0].arguments()[0].elements(), ["baz"])
}

///|
test "upstream options::parameters_with_both_long_and_short_may_not_use_both" {
  let compilation = try! options_upstream_compilation(
    "[arg('bar', long='bar', short='b')]\nfoo bar:\n",
  )
  try
    parse_invocations(compilation, ["foo", "--bar", "baz", "-b", "baz"])
  catch {
    DuplicateOption(recipe="foo", option="-b") => ()
    error => fail("unexpected invocation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected duplicate option error")
  }
}
