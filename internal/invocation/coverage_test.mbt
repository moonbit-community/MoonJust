///|
test "invocation diagnostics cover every structured error shape" {
  let source = @source.Source::from_text(
    @source.SourceId::new(9910),
    "invocation.coverage",
    "run x:\n",
  )
  let first = @source.Span::new(source.id(), 0, 1)
  let second = @source.Span::new(source.id(), 1, 2)
  let errors : Array[InvocationError] = [
    NoRecipes,
    NoDefaultRecipe,
    DefaultRecipeRequiresArguments(recipe="run", minimum=2),
    UnknownRecipe(recipe="missing"),
    UnknownRecipeSuggested(
      recipe="mising",
      suggestion="missing",
      alias_target=None,
    ),
    UnknownRecipeSuggested(
      recipe="mising",
      suggestion="missing",
      alias_target=Some("build"),
    ),
    UnknownSubmodule(name="tools", suggestion=None),
    UnknownSubmodule(name="tools", suggestion=Some("tool")),
    ExpectedSubmoduleFoundRecipe(path="tools.just"),
    DisabledRecipe(name="build", modules=["a"], is_alias=false),
    DisabledRecipe(name="build", modules=["a", "b"], is_alias=true),
    OptionalModuleAbsent(module_path="optional.just"),
    Evaluation(
      @evaluator.EvaluationError::UndefinedVariable(name="x", span=first),
    ),
    InvalidArgumentAttribute(recipe="run", detail="bad", span=Some(first)),
    InvalidArgumentPattern(
      recipe="run",
      detail="bad",
      cause="cause",
      span=Some(first),
    ),
    DuplicateArgumentAttribute(name="x", first~, second~),
    DuplicateDefinitionOption(recipe="run", option="x", span=first),
    InvalidOption(argument="--bad"),
    UnknownOption(recipe="run", option="--bad"),
    FlagWithValue(recipe="run", option="--flag"),
    NonFinalOptionWithValue(recipe="run", option="--value"),
    OptionMissingValue(recipe="run", option="--value"),
    DuplicateOption(recipe="run", option="--value"),
    MissingOption(recipe="run", option="--value"),
    PositionalArgumentCountMismatch(
      recipe="run",
      found=0,
      minimum=1,
      maximum=None,
      usage="just run x",
    ),
    PositionalArgumentCountMismatch(
      recipe="run",
      found=2,
      minimum=1,
      maximum=Some(2),
      usage="just run x",
    ),
    PositionalArgumentCountMismatch(
      recipe="run",
      found=3,
      minimum=1,
      maximum=Some(2),
      usage="just run x",
    ),
    PositionalArgumentCountMismatch(
      recipe="run",
      found=1,
      minimum=1,
      maximum=Some(1),
      usage="just run x",
    ),
    ArgumentTooFewValues(recipe="run", parameter="x", found=0, minimum=1),
    ArgumentTooManyValues(recipe="run", parameter="x", found=2, maximum=1),
    ArgumentPatternMismatch(recipe="run", parameter="x", argument="z", patterns=[
      "a", "b",
    ]),
  ]
  for error in errors {
    assert_true(error.code().has_prefix("MJ-INV-"))
    assert_true(error.message().length() > 0)
    let _ = error.span()
    let _ = try! error.to_diagnostic()
  }
  let pattern : InvocationError = InvalidArgumentPattern(
    recipe="run",
    detail="bad",
    cause="cause",
    span=Some(first),
  )
  guard pattern.to_diagnostic() is Some(diagnostic) else {
    fail("expected a diagnostic for a span-bearing error")
  }
  assert_true(diagnostic.trailers().length() == 1)
  let duplicate : InvocationError = DuplicateArgumentAttribute(
    name="x",
    first~,
    second~,
  )
  guard duplicate.to_diagnostic() is Some(diagnostic) else {
    fail("expected duplicate argument diagnostic")
  }
  assert_eq(diagnostic.related(), [first])
  ignore(second)
}

///|
fn assert_invalid_argument_metadata(
  fixture : String,
  expected : String,
) -> Unit raise {
  let compilation = compile_fixture(fixture)
  try @invocation.parse_invocations(compilation, ["run"]) catch {
    InvalidArgumentAttribute(detail~, ..) =>
      if !detail.contains(expected) {
        fail(
          "fixture `" +
          fixture +
          "` expected `" +
          expected +
          "`, got `" +
          detail +
          "`",
        )
      }
    error => fail("unexpected argument metadata error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid argument metadata")
  }
}

///|
test "argument metadata rejects malformed literal names modes and bounds" {
  let cases = [
    ("[arg(true)]\nrun x:\n", "requires a string literal"),
    ("[arg('missing', long)]\nrun x:\n", "undefined argument"),
    ("[arg('x', long='')]\nrun x:\n", "is empty"),
    ("[arg('x', long='a=b')]\nrun x:\n", "contains equal sign"),
    ("[arg('x', short='xy')]\nrun x:\n", "multiple characters"),
    ("[arg('x', long, flag=true)]\nrun x:\n", "takes no value"),
    ("[arg('x', long, value)]\nrun x:\n", "requires value"),
    ("[arg('x', long, multiple=true)]\nrun x:\n", "takes no value"),
    ("set lists\n[arg('x', min)]\nrun *x:\n", "requires value"),
    ("set lists\n[arg('x', min=true)]\nrun *x:\n", "string literals"),
    ("set lists\n[arg('x', min='')]\nrun *x:\n", "invalid `min` value"),
    ("set lists\n[arg('x', min='01')]\nrun *x:\n", "invalid `min` value"),
    ("set lists\n[arg('x', min='x')]\nrun *x:\n", "invalid `min` value"),
    (
      "set lists\n[arg('x', min='999999999999999999999999999999')]\nrun *x:\n", "number too large",
    ),
    ("[arg('x', pattern)]\nrun x:\n", "requires value"),
    ("[arg('x', help)]\nrun x:\n", "requires a string literal"),
    ("[arg('x', flag)]\nrun x:\n", "only valid with"),
    ("[arg('x', value='v')]\nrun x:\n", "only valid with"),
    ("[arg('x', multiple)]\nrun x:\n", "only valid with"),
    (
      "set lists\n[arg('x', long, flag, value='v')]\nrun x:\n", "both `flag` and `value`",
    ),
    (
      "set lists\n[arg('x', long, flag, pattern='x')]\nrun x:\n", "both `flag` and `pattern`",
    ),
    (
      "set lists\n[arg('x', long, flag)]\nrun x='v':\n", "may not have a default",
    ),
    ("set lists\n[arg('x', min='1')]\nrun x:\n", "only valid with"),
    ("set lists\n[arg('x', max='1')]\nrun x:\n", "only valid with"),
    (
      "set lists\n[arg('x', long, multiple, min='2', max='1')]\nrun *x:\n", "exceeds `max`",
    ),
    ("[arg('x', long, long='other')]\nrun x:\n", "duplicate key"),
  ]
  for row in cases {
    let (fixture, expected) = row
    assert_invalid_argument_metadata(fixture, expected)
  }
}

///|
test "argument metadata rejects duplicate attributes and option definitions" {
  let duplicate_attribute = compile_fixture(
    "[arg('x', long)]\n[arg('x', short)]\nrun x:\n",
  )
  try @invocation.parse_invocations(duplicate_attribute, ["run"]) catch {
    DuplicateArgumentAttribute(name~, ..) => assert_eq(name, "x")
    error => fail("unexpected duplicate attribute error: \{Repr(error)}")
  } noraise {
    _ => fail("expected duplicate argument attribute")
  }
  for
    row in [
      ("[arg('x', long)]\n[arg('y', long='x')]\nrun x y:\n", "--x"),
      ("[arg('x', short='z')]\n[arg('y', short='z')]\nrun x y:\n", "-z"),
    ] {
    let (fixture, option) = row
    let compilation = compile_fixture(fixture)
    try @invocation.parse_invocations(compilation, ["run"]) catch {
      DuplicateDefinitionOption(option=actual, ..) => assert_eq(actual, option)
      error => fail("unexpected duplicate option error: \{Repr(error)}")
    } noraise {
      _ => fail("expected duplicate option definition")
    }
  }
}

///|
test "list-only argument properties require list mode independently" {
  for
    row in [
      ("[arg('x', long, flag)]\nrun x:\n", "flag"),
      ("[arg('x', long, multiple)]\nrun x:\n", "multiple"),
      ("[arg('x', min='1')]\nrun *x:\n", "min"),
      ("[arg('x', max='1')]\nrun *x:\n", "max"),
    ] {
    let (fixture, expected) = row
    assert_invalid_argument_metadata(fixture, expected)
  }
}
