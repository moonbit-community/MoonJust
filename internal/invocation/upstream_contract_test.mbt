///|
fn compile_invocation_contract(text : String) -> @semantic.Compilation raise {
  @semantic.compile_source(
    @source.Source::from_text(
      @source.SourceId::new(1900),
      "upstream-invocation-contract",
      text,
    ),
    allow_unstable=true,
  )
}

///|
fn invocation_values(
  invocation : @invocation.Invocation,
) -> Array[Array[String]] {
  invocation.arguments().map(fn(value) { value.elements().to_owned() })
}

///|
fn assert_invocation_success(
  source : String,
  args : ArrayView[String],
  recipes : ArrayView[String],
  expected : ArrayView[Array[Array[String]]],
) -> Unit raise {
  let parsed = @invocation.parse_invocations(
    compile_invocation_contract(source),
    args,
  )
  assert_eq(parsed.length(), recipes.length())
  for index, recipe in recipes {
    assert_eq(parsed[index].recipe(), recipe)
    assert_eq(invocation_values(parsed[index]), expected[index])
  }
}

///|
fn assert_invocation_error(
  source : String,
  args : ArrayView[String],
  code : String,
  message : String,
) -> Unit raise {
  let compilation = compile_invocation_contract(source)
  try @invocation.parse_invocations(compilation, args) catch {
    error => {
      assert_eq(error.code(), code)
      assert_eq(error.message(), message)
    }
  } noraise {
    _ => fail("invocation contract unexpectedly succeeded")
  }
}

///|
test "contract JUST-1.57.0-1033 invocation_parser::tests::complex_grouping" {
  assert_invocation_success(
    "FOO A B='blarg':\n  echo foo: {{A}} {{B}}\n\nBAR X:\n  echo bar: {{X}}\n\nBAZ +Z:\n  echo baz: {{Z}}\n",
    ["BAR", "0", "FOO", "1", "2", "BAZ", "3", "4", "5"],
    ["BAR", "FOO", "BAZ"],
    [[["0"]], [["1"], ["2"]], [["3", "4", "5"]]],
  )
}

///|
test "contract JUST-1.57.0-1034 invocation_parser::tests::default_recipe_requires_arguments" {
  assert_invocation_error(
    "foo bar:",
    [],
    "MJ-INV-0002",
    "recipe `foo` cannot be used as default recipe since it requires at least 1 argument",
  )
}

///|
test "contract JUST-1.57.0-1035 invocation_parser::tests::long_argument" {
  assert_invocation_success(
    "[arg('bar', long='bar')]\nfoo bar:\n",
    ["foo", "--bar", "baz"],
    ["foo"],
    [[["baz"]]],
  )
}

///|
test "contract JUST-1.57.0-1036 invocation_parser::tests::long_argument_terminator" {
  assert_invocation_success(
    "[arg('bar', long='bar')]\nfoo baz qux='qux' bar='bar':\n",
    ["foo", "--", "--bar"],
    ["foo"],
    [[["--bar"], [], []]],
  )
}

///|
test "contract JUST-1.57.0-1037 invocation_parser::tests::long_argument_with_positional" {
  assert_invocation_success(
    "[arg('bar', long='bar')]\nfoo baz bar:\n",
    ["foo", "qux", "--bar", "baz"],
    ["foo"],
    [[["qux"], ["baz"]]],
  )
}

///|
test "contract JUST-1.57.0-1040 invocation_parser::tests::multiple_unknown" {
  assert_invocation_error(
    "foo:",
    ["bar", "baz"],
    "MJ-INV-0003",
    "justfile does not contain recipe `bar`",
  )
}

///|
test "contract JUST-1.57.0-1042 invocation_parser::tests::no_recipes" {
  assert_invocation_error("", [], "MJ-INV-0001", "justfile contains no recipes")
}

///|
test "contract JUST-1.57.0-1047 invocation_parser::tests::repeatable_long_option" {
  assert_invocation_success(
    "[arg('bar', long='bar')]\nfoo +bar:\n",
    ["foo", "--bar", "a", "--bar", "b"],
    ["foo"],
    [[["a", "b"]]],
  )
}

///|
test "contract JUST-1.57.0-1048 invocation_parser::tests::single_argument_count_mismatch" {
  assert_invocation_error(
    "foo bar:",
    ["foo"],
    "MJ-INV-0012",
    "recipe `foo` got 0 positional arguments but takes 1\nusage:\n    just foo bar",
  )
}

///|
test "contract JUST-1.57.0-1049 invocation_parser::tests::single_no_arguments" {
  assert_invocation_success("foo:", ["foo"], ["foo"], [[]])
}

///|
test "contract JUST-1.57.0-1050 invocation_parser::tests::single_unknown" {
  assert_invocation_error(
    "foo:",
    ["bar"],
    "MJ-INV-0003",
    "justfile does not contain recipe `bar`",
  )
}

///|
test "contract JUST-1.57.0-1051 invocation_parser::tests::single_with_argument" {
  assert_invocation_success("foo bar:", ["foo", "baz"], ["foo"], [[["baz"]]])
}
