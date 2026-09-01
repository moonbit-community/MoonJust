///|
fn upstream_parser_source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(804), "justfile", text)
}

///|
test "parser empty" {
  let ast = try! parse(upstream_parser_source(""))
  assert_true(ast.items().is_empty())
}

///|
test "parser alias_single" {
  let ast = try! parse(upstream_parser_source("alias t := test"))
  guard ast.items()[0] is Alias(alias_item) else { fail("expected alias") }
  assert_eq(alias_item.name(), "t")
  assert_eq(alias_item.target(), "test")
}

///|
test "parser assignment" {
  let ast = try! parse(upstream_parser_source("x := 'hello'"))
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  assert_eq(assignment.name(), "x")
  assert_eq(assignment.value().kind(), "string")
}

///|
test "parser backtick" {
  let ast = try! parse(upstream_parser_source("x := `hello`"))
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  assert_eq(assignment.value().kind(), "backtick")
}

///|
test "parser comment" {
  let ast = try! parse(upstream_parser_source("# foo"))
  guard ast.items()[0] is Comment(text~, ..) else { fail("expected comment") }
  assert_eq(text, "# foo")
}

///|
test "parser empty_body" {
  let ast = try! parse(upstream_parser_source("a:"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.name(), "a")
  assert_true(recipe.lines().is_empty())
}

///|
test "parser export" {
  let ast = try! parse(upstream_parser_source("export x := 'hello'"))
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  assert_true(assignment.exported())
}

///|
test "parser group" {
  let ast = try! parse(upstream_parser_source("x := (y)"))
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  assert_eq(assignment.value().kind(), "parenthesized")
}

///|
test "parser import" {
  let ast = try! parse(upstream_parser_source("import 'foo.just'"))
  guard ast.items()[0] is Import(import_item) else { fail("expected import") }
  assert_eq(import_item.path().cooked(), "foo.just")
  assert_true(!import_item.optional())
}

///|
test "parser optional_import" {
  let ast = try! parse(upstream_parser_source("import? 'foo.just'"))
  guard ast.items()[0] is Import(import_item) else { fail("expected import") }
  assert_true(import_item.optional())
}
