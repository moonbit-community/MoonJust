///|
fn invocation_compilation(text : String) -> @semantic.Compilation raise {
  @semantic.compile_source(
    @source.Source::from_text(@source.SourceId::new(801), "justfile", text),
    allow_unstable=true,
  )
}

///|
test "invocation single_no_arguments" {
  let compilation = try! invocation_compilation("foo:\n")
  let invocations = try! parse_invocations(compilation, ["foo"])
  assert_eq(invocations.length(), 1)
  assert_eq(invocations[0].recipe(), "foo")
  assert_true(invocations[0].arguments().is_empty())
}

///|
test "invocation single_with_argument" {
  let compilation = try! invocation_compilation("foo bar:\n")
  let invocations = try! parse_invocations(compilation, ["foo", "baz"])
  assert_eq(invocations.length(), 1)
  assert_eq(invocations[0].recipe(), "foo")
  assert_eq(invocations[0].arguments()[0].elements(), ["baz"])
}

///|
test "invocation single_argument_count_mismatch" {
  let compilation = try! invocation_compilation("foo bar:\n")
  try parse_invocations(compilation, ["foo"]) catch {
    PositionalArgumentCountMismatch(recipe="foo", minimum=1, ..) => ()
    _ => fail("unexpected invocation error")
  } noraise {
    _ => fail("expected positional argument mismatch")
  }
}

///|
test "invocation single_unknown" {
  let compilation = try! invocation_compilation("foo:\n")
  try parse_invocations(compilation, ["bar"]) catch {
    UnknownRecipe(recipe="bar") => ()
    _ => fail("unexpected invocation error")
  } noraise {
    _ => fail("expected unknown recipe")
  }
}

///|
test "invocation multiple_unknown" {
  let compilation = try! invocation_compilation("foo:\n")
  try parse_invocations(compilation, ["bar", "baz"]) catch {
    UnknownRecipe(recipe="bar") => ()
    _ => fail("unexpected invocation error")
  } noraise {
    _ => fail("expected first unknown recipe")
  }
}

///|
test "invocation complex_grouping" {
  let compilation = try! invocation_compilation(
    "FOO A B='blarg':\n    @echo foo\n" +
    "BAR X:\n    @echo bar\n" +
    "BAZ +Z:\n    @echo baz\n",
  )
  let invocations = try! parse_invocations(compilation, [
    "BAR", "0", "FOO", "1", "2", "BAZ", "3", "4", "5",
  ])
  assert_eq(invocations.length(), 3)
  assert_eq(invocations[0].recipe(), "BAR")
  assert_eq(invocations[0].arguments()[0].elements(), ["0"])
  assert_eq(invocations[1].recipe(), "FOO")
  assert_eq(invocations[1].arguments()[0].elements(), ["1"])
  assert_eq(invocations[1].arguments()[1].elements(), ["2"])
  assert_eq(invocations[2].recipe(), "BAZ")
  assert_eq(invocations[2].arguments()[0].elements(), ["3", "4", "5"])
}

///|
test "invocation long_argument" {
  let compilation = try! invocation_compilation(
    "[arg('bar', long='bar')]\nfoo bar:\n    @:\n",
  )
  let invocations = try! parse_invocations(compilation, ["foo", "--bar", "baz"])
  assert_eq(invocations[0].recipe(), "foo")
  assert_eq(invocations[0].arguments()[0].elements(), ["baz"])
}

///|
test "invocation repeatable_long_option" {
  let compilation = try! invocation_compilation(
    "[arg('bar', long='bar')]\nfoo +bar:\n    @:\n",
  )
  let invocations = try! parse_invocations(compilation, [
    "foo", "--bar", "a", "--bar", "b",
  ])
  assert_eq(invocations[0].arguments()[0].elements(), ["a", "b"])
}

///|
test "invocation long_argument_with_positional" {
  let compilation = try! invocation_compilation(
    "[arg('bar', long='bar')]\nfoo baz bar:\n    @:\n",
  )
  let invocations = try! parse_invocations(compilation, [
    "foo", "qux", "--bar", "baz",
  ])
  assert_eq(invocations[0].arguments()[0].elements(), ["qux"])
  assert_eq(invocations[0].arguments()[1].elements(), ["baz"])
}

///|
test "invocation long_argument_terminator" {
  let compilation = try! invocation_compilation(
    "[arg('bar', long='bar')]\nfoo baz qux='qux' bar='bar':\n    @:\n",
  )
  let invocations = try! parse_invocations(compilation, ["foo", "--", "--bar"])
  assert_eq(invocations[0].arguments()[0].elements(), ["--bar"])
  assert_true(invocations[0].arguments()[1].elements().is_empty())
  assert_true(invocations[0].arguments()[2].elements().is_empty())
}

///|
test "invocation no_recipes" {
  let compilation = try! invocation_compilation("")
  try parse_invocations(compilation, []) catch {
    NoRecipes => ()
    _ => fail("unexpected invocation error")
  } noraise {
    _ => fail("expected no recipes")
  }
}

///|
test "invocation default_recipe_requires_arguments" {
  let compilation = try! invocation_compilation("foo bar:\n    @:\n")
  try parse_invocations(compilation, []) catch {
    DefaultRecipeRequiresArguments(recipe="foo", minimum=1) => ()
    _ => fail("unexpected invocation error")
  } noraise {
    _ => fail("expected default argument error")
  }
}
