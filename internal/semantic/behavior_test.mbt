///|
fn semantic_source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(702), "justfile", text)
}

///|
test "semantic compilation preserves declaration order and settings" {
  let source = semantic_source(
    "set quiet\nexport NAME := \"value\"\n" +
    "[group(\"build\")]\nbuild:\n  echo {{NAME}}\n",
  )
  let compiled = try! compile(try! @parser.parse(source))
  assert_true(compiled.settings().bool("quiet"))
  assert_eq(compiled.variable_names(), ["NAME"])
  assert_eq(compiled.recipe_names(), ["build"])
  assert_eq(compiled.recipe_attributes("build").unwrap().groups(), ["build"])
}

///|
test "semantic compilation rejects duplicate recipes" {
  let ast = try! @parser.parse(semantic_source("same:\nsame:\n"))
  try compile(ast) catch {
    DuplicateRecipe(name="same", ..) => ()
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected duplicate recipe error")
  }
}
