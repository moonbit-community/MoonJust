///|
fn justfile_source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(31), "justfile", text)
}

///|
test "top-level parser builds assignments aliases settings recipes and imports" {
  let source = justfile_source(
    (
      #|export greeting := "hello"
      #|alias hi := greet
      #|set shell := ["sh", "-cu"]
      #|import? "common.just"
      #|greet name +rest: hi && deploy
      #|  @echo {{name}}
      #|deploy:
      #|  echo deploy
    ),
  )
  let ast = @parser.parse(source)
  assert_eq(ast.source_id(), source.id())
  let items = ast.items()
  assert_true(items[0] is Assignment(item) && item.exported())
  assert_true(items[1] is Alias(item) && item.target() == "greet")
  assert_true(items[2] is Setting(item) && item.name() == "shell")
  assert_true(items[3] is Import(item) && item.optional())
  guard items[4] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.name(), "greet")
  assert_eq(recipe.parameters().length(), 2)
  assert_eq(recipe.parameters()[1].variadic_minimum(), 1)
  assert_eq(recipe.dependencies().length(), 1)
  assert_eq(recipe.subsequent_dependencies().length(), 1)
  assert_eq(recipe.lines().length(), 1)
  assert_true(recipe.lines()[0].fragments()[0] is Text(..))
  guard items[5] is Recipe(deploy) else { fail("expected deploy") }
  assert_eq(deploy.name(), "deploy")

  let star = @parser.parse(justfile_source("collect *items:\n"))
  guard star.items()[0] is Recipe(star_recipe) else {
    fail("expected star-variadic recipe")
  }
  assert_true(star_recipe.parameters()[0].variadic())
  assert_eq(star_recipe.parameters()[0].variadic_minimum(), 0)
}

///|
test "attributes attach to the following recipe and validate names" {
  let source = justfile_source(
    (
      #|[private, group("build"), working-directory: "sub"]
      #|build:
      #|  echo ok
    ),
  )
  let ast = @parser.parse(source)
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.attributes().length(), 3)
  assert_eq(recipe.attributes()[1].name(), "group")
  let invalid = justfile_source("[does-not-exist]\nfoo:\n")
  try @parser.parse(invalid) catch {
    UnknownAttribute(name="does-not-exist", ..) => ()
    _ => fail("unexpected parser error")
  } noraise {
    _ => fail("expected unknown attribute")
  }
}

///|
test "empty and extraneous attributes are rejected before execution" {
  try @parser.parse(justfile_source("[]\nhello:\n  @exit 100\n")) catch {
    UnexpectedToken(expected="identifier", found=BracketR, ..) => ()
    error => fail("unexpected empty attribute error: \{Repr(error)}")
  } noraise {
    _ => fail("expected empty attribute error")
  }
  for
    text in [
      "[no-exit-message]\n# comment\nhello:\n", "[no-exit-message]\n\nhello:\n",
    ] {
    try @parser.parse(justfile_source(text)) catch {
      ExtraneousAttribute(span~) => assert_eq(span.start_byte(), 0)
      error => fail("unexpected extraneous attribute error: \{Repr(error)}")
    } noraise {
      _ => fail("expected extraneous attribute error")
    }
  }
  try @parser.parse(justfile_source("[confirm]\n")) catch {
    UnexpectedToken(found=Eof, span~, ..) => {
      assert_eq(span.start_byte(), 8)
      assert_eq(span.end_byte(), 9)
    }
    error => fail("unexpected dangling attribute error: \{Repr(error)}")
  } noraise {
    _ => fail("expected dangling attribute error")
  }
}

///|
test "recipe parameter path joins require parentheses" {
  try @parser.parse(justfile_source("build path='a' / 'b':\n")) catch {
    UnexpectedToken(found=Slash, ..) => ()
    error => fail("unexpected unparenthesized join error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unparenthesized join error")
  }
  let ast = try! @parser.parse(justfile_source("build path=('a' / 'b'):\n"))
  guard ast.items()[0] is Recipe(recipe) &&
    recipe.parameters()[0].default_value() is Some(Parenthesized(..)) else {
    fail("expected parenthesized path-join parameter default")
  }
}

///|
test "default expression stops before exported plus variadic parameter" {
  let ast = try! @parser.parse(
    justfile_source("foo value=('a') +$flags='-q':\n"),
  )
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.parameters().length(), 2)
  assert_eq(recipe.parameters()[0].name(), "value")
  assert_true(recipe.parameters()[0].default_value() is Some(_))
  assert_eq(recipe.parameters()[1].name(), "flags")
  assert_true(recipe.parameters()[1].variadic())
  assert_true(recipe.parameters()[1].exported())
}

///|
test "user function definitions retain parameters trailing comma and body" {
  let source = @source.Source::from_text(
    @source.SourceId::new(801),
    "justfile",
    "f(first, second,) := first + second\n",
  )
  let ast = try! @parser.parse(source)
  guard ast.items()[0] is Function(definition) else {
    fail("expected function definition")
  }
  assert_eq(definition.name(), "f")
  assert_eq(definition.parameters().map(fn(parameter) { parameter.name() }), [
    "first", "second",
  ])
  assert_true(definition.body() is Binary(operator=Concat, ..))
}
