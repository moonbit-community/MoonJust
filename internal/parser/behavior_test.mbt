///|
fn parser_source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(701), "justfile", text)
}

///|
test "parser builds recipes, parameters, aliases, and settings" {
  let source = parser_source(
    "set shell := [\"sh\", \"-cu\"]\n" +
    "alias hi := hello\n" +
    "hello name +rest: hi\n" +
    "  @echo {{name}}\n",
  )
  let ast = try! parse(source)
  assert_eq(ast.items().length(), 3)
  guard ast.items()[1] is Alias(alias_item) else { fail("expected alias") }
  assert_eq(alias_item.name(), "hi")
  assert_eq(alias_item.target(), "hello")
  guard ast.items()[2] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.name(), "hello")
  assert_eq(recipe.parameters().length(), 2)
  assert_true(recipe.parameters()[1].variadic())
  assert_eq(recipe.dependencies().length(), 1)
  assert_eq(recipe.lines().length(), 1)
}

///|
test "parser rejects dangling attributes" {
  try parse(parser_source("[private]\n")) catch {
    UnexpectedToken(found=Eof, ..) => ()
    error => fail("unexpected parser error: \{Repr(error)}")
  } noraise {
    _ => fail("expected dangling attribute error")
  }
}
