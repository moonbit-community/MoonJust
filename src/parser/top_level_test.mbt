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
