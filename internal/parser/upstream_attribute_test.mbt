///|
test "attribute name preserves kebab-case" {
  let source = @source.Source::from_text(
    @source.SourceId::new(802),
    "justfile",
    "[no-exit-message]\nfoo:\n    @:\n",
  )
  let ast = try! parse(source)
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.attributes().length(), 1)
  assert_eq(recipe.attributes()[0].name(), "no-exit-message")
}
