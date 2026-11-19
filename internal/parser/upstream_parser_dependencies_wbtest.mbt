///|
test "upstream parser::tests::recipe_dependency_multiple" {
  let ast = try! parse(parser_upstream_source("foo: bar baz\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.dependencies().length(), 2)
  assert_eq(recipe.dependencies()[0].name(), "bar")
  assert_eq(recipe.dependencies()[1].name(), "baz")
}

///|
test "upstream parser::tests::recipe_dependency_parenthesis" {
  let ast = try! parse(parser_upstream_source("foo: (bar)\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.dependencies().length(), 1)
  assert_eq(recipe.dependencies()[0].name(), "bar")
  assert_true(recipe.dependencies()[0].arguments().is_empty())
}

///|
test "upstream parser::tests::recipe_dependency_argument_string" {
  let ast = try! parse(parser_upstream_source("foo: (bar 'baz')\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.dependencies().length(), 1)
  assert_eq(recipe.dependencies()[0].name(), "bar")
  assert_eq(
    recipe.dependencies()[0].arguments()[0].semantic_key(),
    "string:raw(baz)",
  )
}

///|
test "upstream parser::tests::recipe_subsequent" {
  let ast = try! parse(parser_upstream_source("foo: && bar\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.subsequent_dependencies().length(), 1)
  assert_eq(recipe.subsequent_dependencies()[0].name(), "bar")
}

///|
test "upstream parser::tests::recipe_dependency_module" {
  let ast = try! parse(parser_upstream_source("foo: bar::baz\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.dependencies()[0].name(), "bar::baz")
}

///|
test "upstream parser::tests::recipe_dependency_module_mixed" {
  let ast = try! parse(parser_upstream_source("foo: bar::baz qux\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.dependencies().length(), 2)
  assert_eq(recipe.dependencies()[0].name(), "bar::baz")
  assert_eq(recipe.dependencies()[1].name(), "qux")
}

///|
test "upstream parser::tests::recipe_dependency_parenthesis_module" {
  let ast = try! parse(parser_upstream_source("foo: (bar::baz)\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.dependencies()[0].name(), "bar::baz")
}

///|
test "upstream parser::tests::recipe_dependency_argument_identifier" {
  let ast = try! parse(parser_upstream_source("foo: (bar baz)\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.dependencies()[0].name(), "bar")
  assert_eq(recipe.dependencies()[0].arguments()[0].semantic_key(), "var:baz")
}

///|
test "upstream parser::tests::recipe_dependency_argument_concatenation" {
  let ast = try! parse(
    parser_upstream_source("foo: (bar 'a' + 'b' 'c' + 'd')\n"),
  )
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.dependencies()[0]
    .arguments()
    .map(fn(value) { value.semantic_key() })
    .join(","),
    "binary:concat(string:raw(a),string:raw(b)),binary:concat(string:raw(c),string:raw(d))",
  )
}
