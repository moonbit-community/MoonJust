///|
fn compile_fixture(text : String) -> @semantic.Compilation raise {
  @semantic.compile_source(
    @source.Source::from_text(@source.SourceId::new(1), "justfile", text),
  )
}

///|
fn values(invocation : @invocation.Invocation) -> Array[Array[String]] {
  invocation.arguments().map(fn(value) { value.elements().to_owned() })
}

///|
test "positional defaults variadics and multiple invocations are grouped" {
  let compilation = compile_fixture("foo a:\n\nbar +values:\n")
  let parsed = @invocation.parse_invocations(compilation, [
    "foo", "A", "bar", "one", "two",
  ])
  assert_eq(parsed.length(), 2)
  assert_eq(parsed[0].recipe(), "foo")
  assert_eq(values(parsed[0]), [["A"]])
  assert_eq(parsed[1].recipe(), "bar")
  assert_eq(values(parsed[1]), [["one", "two"]])
  let defaulted = compile_fixture("defaulted value='fallback':\n")
  assert_eq(
    values(@invocation.parse_invocations(defaulted, ["defaulted"])[0]),
    [[]],
  )
}

///|
test "long short combined repeatable and terminator options match upstream" {
  let compilation = compile_fixture(
    "set lists\n" +
    "[arg('a', short='a', value='A')]\n" +
    "[arg('b', short='b', flag)]\n" +
    "[arg('c', long='count', multiple)]\n" +
    "run a b c *rest:\n",
  )
  let parsed = @invocation.parse_invocations(compilation, [
      "run", "-ab", "--count=one", "--count", "two", "--", "--literal",
    ])[0]
  assert_eq(values(parsed), [["A"], ["true"], ["one", "two"], ["--literal"]])
}

///|
test "options and positional arguments may be intermixed" {
  let compilation = compile_fixture(
    "[arg('b', long='b')]\n" + "[arg('d', short='d')]\n" + "run a b c d e:\n",
  )
  let parsed = @invocation.parse_invocations(compilation, [
      "run", "A", "-d", "D", "C", "--b", "B", "E",
    ])[0]
  assert_eq(values(parsed), [["A"], ["B"], ["C"], ["D"], ["E"]])
}

///|
test "arguments beginning with dash are positional when recipe has no options" {
  let compilation = compile_fixture("run *values:\n")
  let parsed = @invocation.parse_invocations(compilation, [
      "run", "--unknown", "-x", "-",
    ])[0]
  assert_eq(values(parsed), [["--unknown", "-x", "-"]])
}

///|
test "aliases and explicit default recipe are resolved" {
  let compilation = compile_fixture(
    "first:\n\n[default]\nchosen *args:\n\nalias c := chosen\nalias d := c\n",
  )
  assert_eq(
    @invocation.parse_invocations(compilation, [])[0].recipe(),
    "chosen",
  )
  assert_eq(
    @invocation.parse_invocations(compilation, ["d", "x"])[0].recipe(),
    "chosen",
  )
}

///|
test "default recipe requiring arguments has a distinct upstream error" {
  let compilation = compile_fixture("run required:\n")
  try @invocation.parse_invocations(compilation, []) catch {
    error => {
      assert_eq(error.code(), "MJ-INV-0002")
      assert_eq(
        error.message(),
        "recipe `run` cannot be used as default recipe since it requires at least 1 argument",
      )
    }
  } noraise {
    _ => fail("expected default recipe failure")
  }
}

///|
test "missing positional argument includes upstream short usage" {
  let compilation = compile_fixture("run required optional='x':\n")
  try @invocation.parse_invocations(compilation, ["run"]) catch {
    error => {
      assert_eq(error.code(), "MJ-INV-0012")
      assert_eq(
        error.message(),
        "recipe `run` got 0 positional arguments but takes at least 1\n" +
        "usage:\n    just run required [optional]",
      )
    }
  } noraise {
    _ => fail("expected positional count failure")
  }
}

///|
test "option error branches preserve upstream messages" {
  let compilation = compile_fixture(
    "set lists\n" +
    "[arg('flag', long, flag)]\n" +
    "[arg('value', short='v')]\n" +
    "run flag value:\n",
  )
  let cases = [
    (["run", "--unknown"], "recipe `run` does not have option `--unknown`"),
    (["run", "--flag=yes"], "recipe `run` flag `--flag` does not take value"),
    (["run", "-v"], "recipe `run` option `-v` missing value"),
    (
      ["run", "--flag", "--flag", "-v", "x"],
      "recipe `run` option `--flag` cannot be passed more than once",
    ),
  ]
  for case in cases {
    let (arguments, expected) = case
    try @invocation.parse_invocations(compilation, arguments) catch {
      error => assert_eq(error.message(), expected)
    } noraise {
      _ => fail("expected option failure")
    }
  }
}

///|
test "a value-taking short option must be final when combined" {
  let compilation = compile_fixture(
    "set lists\n[arg('a', short='a')]\n[arg('b', short='b', flag)]\nrun a b:\n",
  )
  try
    @invocation.parse_invocations(compilation, ["run", "-ab", "value"])
  catch {
    error =>
      assert_eq(
        error.message(),
        "recipe `run` option `-a` takes a value and so must be last when combined with other options",
      )
  } noraise {
    _ => fail("expected non-final value option failure")
  }
}

///|
test "required options count constraints and anchored patterns are enforced" {
  let required = compile_fixture("[arg('x', long='x')]\nrun x:\n")
  try @invocation.parse_invocations(required, ["run"]) catch {
    error => assert_eq(error.message(), "recipe `run` requires option `--x`")
  } noraise {
    _ => fail("expected required option failure")
  }
  let constrained = compile_fixture(
    "set lists\n" +
    "[arg('x', long='x', multiple, min='2', max='2', pattern='[0-9]+')]\n" +
    "run x:\n",
  )
  try @invocation.parse_invocations(constrained, ["run", "--x", "1"]) catch {
    error =>
      assert_eq(
        error.message(),
        "recipe `run` parameter `x` got 1 value but takes at least 2",
      )
  } noraise {
    _ => fail("expected minimum failure")
  }
  try
    @invocation.parse_invocations(constrained, ["run", "--x", "abc", "--x", "2"])
  catch {
    error =>
      assert_eq(
        error.message(),
        "argument `abc` passed to recipe `run` parameter `x` does not match pattern `[0-9]+`",
      )
  } noraise {
    _ => fail("expected pattern failure")
  }
  try
    @invocation.parse_invocations(constrained, [
      "run", "--x", "1", "--x", "2", "--x", "3",
    ])
  catch {
    error =>
      assert_eq(
        error.message(),
        "recipe `run` parameter `x` got 3 values but takes at most 2",
      )
  } noraise {
    _ => fail("expected maximum failure")
  }
}

///|
test "a star variadic with positive min is required even when omitted" {
  let compilation = compile_fixture("[arg('x', min='2')]\nrun *x:\n")
  try @invocation.parse_invocations(compilation, ["run"]) catch {
    PositionalArgumentCountMismatch(minimum~, ..) => assert_eq(minimum, 1)
    _ => fail("unexpected required star variadic error")
  } noraise {
    _ => fail("expected omitted star variadic failure")
  }
  try @invocation.parse_invocations(compilation, ["run", "one"]) catch {
    ArgumentTooFewValues(minimum~, ..) => assert_eq(minimum, 2)
    _ => fail("unexpected star variadic count error")
  } noraise {
    _ => fail("expected star variadic minimum failure")
  }
}

///|
test "patterns are full matches and may contain alternatives" {
  let compilation = compile_fixture(
    "set lists\n[arg('x', pattern=['one', 't.*'])]\nrun x:\n",
  )
  assert_eq(
    values(@invocation.parse_invocations(compilation, ["run", "two"])[0]),
    [["two"]],
  )
  try @invocation.parse_invocations(compilation, ["run", "someone"]) catch {
    error => assert_true(error.message().contains("`one` or `t.*`"))
  } noraise {
    _ => fail("expected anchored pattern failure")
  }
}

///|
test "value and pattern expressions use globals and preceding parameters" {
  let compilation = compile_fixture(
    "BASE := 'baz'\nPATTERN := 'hello.*'\n" +
    "[arg('selected', long, value=prefix + BASE, pattern=PATTERN)]\n" +
    "run prefix selected:\n",
  )
  let parsed = @invocation.parse_invocations(compilation, [
      "run", "hello", "--selected",
    ])[0]
  assert_eq(values(parsed), [["hello"], ["hellobaz"]])
  try
    @invocation.parse_invocations(compilation, ["run", "other", "--selected"])
  catch {
    ArgumentPatternMismatch(argument~, ..) => assert_eq(argument, "otherbaz")
    _ => fail("unexpected evaluated pattern failure")
  } noraise {
    _ => fail("expected evaluated value to be pattern checked")
  }
}

///|
test "multiple value expressions flatten list results for each occurrence" {
  let compilation = compile_fixture(
    "set lists\n[arg('x', long, value=['a', 'b'], multiple)]\nrun x:\n",
  )
  let parsed = @invocation.parse_invocations(compilation, ["run", "--x", "--x"])[0]
  assert_eq(values(parsed), [["a", "b", "a", "b"]])
}

///|
test "effectful value expressions surface typed evaluation failures" {
  let compilation = compile_fixture(
    "[arg('x', long, value=env('MISSING'))]\nrun x:\n",
  )
  try @invocation.parse_invocations(compilation, ["run", "--x"]) catch {
    Evaluation(_) as error => assert_eq(error.code(), "MJ-INV-0016")
    _ => fail("unexpected value evaluation failure")
  } noraise {
    _ => fail("expected effectful value expression failure")
  }
}

///|
test "list-only argument modes and dash-prefixed option names are rejected" {
  let cases = [
    "[arg('x', long, flag)]\nrun x:\n", "[arg('x', long, multiple)]\nrun x:\n", "[arg('x', long='-bad')]\nrun x:\n",
    "[arg('x', short='-')]\nrun x:\n",
  ]
  for fixture in cases {
    let compilation = compile_fixture(fixture)
    try @invocation.parse_invocations(compilation, ["run"]) catch {
      InvalidArgumentAttribute(_) => ()
      _ => fail("unexpected argument mode validation failure")
    } noraise {
      _ => fail("expected invalid argument metadata")
    }
  }
}

///|
test "invalid argument metadata is rejected before argv is consumed" {
  let cases = [
    "[arg('x', short='xx')]\nrun x:\n", "[arg('missing', long)]\nrun x:\n", "[arg('x', pattern='[')]\nrun x:\n",
    "[arg('x', long='same')]\n[arg('y', long='same')]\nrun x y:\n",
  ]
  for fixture in cases {
    let compilation = compile_fixture(fixture)
    try @invocation.parse_invocations(compilation, ["run", "value"]) catch {
      InvalidArgumentAttribute(_) as error =>
        assert_eq(error.code(), "MJ-INV-0004")
      _ => fail("unexpected metadata error")
    } noraise {
      _ => fail("expected invalid metadata")
    }
  }
}

///|
test "no recipes and unknown recipes have stable failures" {
  let empty = compile_fixture("")
  try @invocation.parse_invocations(empty, []) catch {
    NoRecipes as error => assert_eq(error.code(), "MJ-INV-0001")
    _ => fail("unexpected empty justfile error")
  } noraise {
    _ => fail("expected no recipes failure")
  }
  let compilation = compile_fixture("build:\n")
  try @invocation.parse_invocations(compilation, ["missing"]) catch {
    UnknownRecipe(recipe~) => assert_eq(recipe, "missing")
    _ => fail("unexpected unknown recipe error")
  } noraise {
    _ => fail("expected unknown recipe failure")
  }
}
