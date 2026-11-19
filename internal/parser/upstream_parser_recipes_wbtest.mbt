///|
test "upstream parser::tests::empty_multiline" {
  let ast = try! parse(parser_upstream_source("\n\n\n"))
  assert_true(ast.items().all(fn(item) { item is Blank(..) }))
}

///|
test "upstream parser::tests::recipe_quiet" {
  let ast = try! parse(parser_upstream_source("@foo:\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.name(), "foo")
  assert_true(recipe.quiet())
}

///|
test "upstream parser::tests::recipe_multiple" {
  let ast = try! parse(parser_upstream_source("foo:\nbar:\nbaz:\n"))
  assert_eq(ast.items().length(), 3)
  guard ast.items()[0] is Recipe(first) else { fail("expected first recipe") }
  guard ast.items()[1] is Recipe(second) else { fail("expected second recipe") }
  guard ast.items()[2] is Recipe(third) else { fail("expected third recipe") }
  assert_eq(first.name(), "foo")
  assert_eq(second.name(), "bar")
  assert_eq(third.name(), "baz")
}

///|
test "upstream parser::tests::recipe_line_single" {
  let ast = try! parse(parser_upstream_source("foo:\n bar\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.lines().length(), 1)
  guard recipe.lines()[0].fragments()[0] is Text(text~, ..) else {
    fail("expected text fragment")
  }
  assert_eq(text, "bar")
}

///|
test "upstream parser::tests::recipe_line_multiple" {
  let ast = try! parse(
    parser_upstream_source("foo:\n bar\n baz\n {{\"bob\"}}biz\n"),
  )
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.lines().length(), 3)
  guard recipe.lines()[0].fragments()[0] is Text(text~, ..) else {
    fail("expected first text")
  }
  assert_eq(text, "bar")
  guard recipe.lines()[1].fragments()[0] is Text(text~, ..) else {
    fail("expected second text")
  }
  assert_eq(text, "baz")
  guard recipe.lines()[2].fragments()[0] is Interpolation(expression~, ..) else {
    fail("expected interpolation")
  }
  assert_eq(expression.semantic_key(), "string:cooked(bob)")
}

///|
test "upstream parser::tests::single_line_body" {
  let ast = try! parse(parser_upstream_source("a:\n foo\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.lines().length(), 1)
  assert_eq(recipe.lines()[0].source_start_line(), 2)
}

///|
test "upstream parser::tests::trimmed_body" {
  let ast = try! parse(parser_upstream_source("a:\n foo\n\n\n\nb:\n"))
  let recipes = ast
    .items()
    .filter_map(fn(item) {
      match item {
        Recipe(recipe) => Some(recipe)
        _ => None
      }
    })
  assert_eq(recipes.length(), 2)
  assert_eq(recipes[0].name(), "a")
  assert_eq(recipes[0].lines().length(), 1)
  assert_eq(recipes[1].name(), "b")
  assert_true(recipes[1].lines().is_empty())
}

///|
test "upstream parser::tests::parse_shebang" {
  let ast = try! parse(
    parser_upstream_source(
      "practicum := 'hello'\ninstall:\n\t#!/bin/sh\n\tif [[ -f {{practicum}} ]]; then\n\t\treturn\n\tfi\n",
    ),
  )
  guard ast.items()[1] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.name(), "install")
  assert_eq(recipe.lines().length(), 4)
  guard recipe.lines()[1].fragments()[1] is Interpolation(expression~, ..) else {
    fail("expected interpolation")
  }
  assert_eq(expression.semantic_key(), "var:practicum")
}

///|
test "upstream parser::tests::parse_simple_shebang" {
  let ast = try! parse(parser_upstream_source("a:\n #!\n  print(1)\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.lines().length(), 2)
}

///|
test "upstream parser::tests::whitespace" {
  let ast = try! parse(parser_upstream_source(" "))
  assert_true(ast.items().is_empty())
}

///|
test "upstream parser::tests::eof_test" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(891),
      "justfile",
      "x:\ny:\nz:\na b c: x y z",
    ),
  )
  assert_eq(ast.items().length(), 4)
  guard ast.items()[3] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.name(), "a")
  assert_eq(recipe.parameters().map(fn(parameter) { parameter.name() }), [
    "b", "c",
  ])
  assert_eq(recipe.dependencies().map(fn(dependency) { dependency.name() }), [
    "x", "y", "z",
  ])
  assert_true(recipe.lines().is_empty())
}

///|
test "upstream parser::tests::parse_complex" {
  let ast = try! parse(
    parser_upstream_source(
      "x:\ny:\nz:\nfoo := \"xx\"\nbar := foo\ngoodbye := \"y\"\nhello a b    c   : x y    z #hello\n  #! blah\n  #blarg\n  {{ foo + bar}}abc{{ goodbye\t  + \"x\" }}xyz\n  1\n  2\n  3\n",
    ),
  )
  assert_eq(ast.items().length(), 7)
  guard ast.items()[6] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.name(), "hello")
  assert_eq(recipe.parameters().map(fn(parameter) { parameter.name() }), [
    "a", "b", "c",
  ])
  assert_eq(recipe.dependencies().map(fn(dependency) { dependency.name() }), [
    "x", "y", "z",
  ])
  assert_eq(recipe.lines().length(), 6)
  assert_eq(recipe.trailing_comment().unwrap(), "#hello")
}

///|
test "upstream justfile::tests::parse_empty" {
  assert_justfile_parser_items("", 0)
}

///|
test "upstream justfile::tests::parse_multiple" {
  assert_justfile_parser_items("foo:\nbar:\nbaz:\n", 3)
}

///|
test "upstream justfile::tests::eof_test" {
  let ast = try! parse(parser_upstream_source("x:\ny:\nz:\na b c: x y z"))
  assert_eq(ast.items().length(), 4)
  guard ast.items()[3] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.name(), "a")
  assert_eq(recipe.parameters().map(fn(parameter) { parameter.name() }), [
    "b", "c",
  ])
}

///|
test "upstream justfile::tests::parse_shebang" {
  let ast = try! parse(
    parser_upstream_source(
      "practicum := 'hello'\ninstall:\n\t#!/bin/sh\n\tif [[ -f {{practicum}} ]]; then\n\t\treturn\n\tfi\n",
    ),
  )
  guard ast.items()[1] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.lines().length(), 4)
}

///|
test "upstream justfile::tests::parse_simple_shebang" {
  let ast = try! parse(parser_upstream_source("a:\n #!\n  print(1)\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.lines().length(), 2)
}

///|
test "upstream justfile::tests::parse_complex" {
  let ast = try! parse(
    parser_upstream_source(
      "x:\ny:\nz:\nfoo := \"xx\"\nbar := foo\ngoodbye := \"y\"\nhello a b    c   : x y    z #hello\n  #! blah\n  #blarg\n  {{ foo + bar}}abc{{ goodbye\t  + \"x\" }}xyz\n  1\n  2\n  3\n",
    ),
  )
  assert_eq(ast.items().length(), 7)
  guard ast.items()[6] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.parameters().length(), 3)
  assert_eq(recipe.dependencies().length(), 3)
  assert_eq(recipe.lines().length(), 6)
}
