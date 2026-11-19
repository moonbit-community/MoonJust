///|
test "upstream parser::tests::comment_before_alias" {
  let ast = try! parse(parser_upstream_source("# foo\nalias x := y\n"))
  guard ast.items()[0] is Comment(text~, ..) else { fail("expected comment") }
  assert_eq(text, "# foo")
  guard ast.items()[1] is Alias(alias_item) else { fail("expected alias") }
  assert_eq(alias_item.name(), "x")
  assert_eq(alias_item.target(), "y")
}

///|
test "upstream parser::tests::comment_assignment" {
  let ast = try! parse(parser_upstream_source("x := y # foo\n"))
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  assert_eq(assignment.name(), "x")
  assert_eq(assignment.value().semantic_key(), "var:y")
  guard ast.items()[1] is TrailingComment(text~, ..) else {
    fail("expected trailing comment")
  }
  assert_eq(text, "# foo")
}

///|
test "upstream parser::tests::comment_after_alias" {
  let ast = try! parse(parser_upstream_source("alias x := y # foo\n"))
  guard ast.items()[0] is Alias(alias_item) else { fail("expected alias") }
  assert_eq(alias_item.name(), "x")
  guard ast.items()[1] is TrailingComment(text~, ..) else {
    fail("expected trailing comment")
  }
  assert_eq(text, "# foo")
}

///|
test "upstream parser::tests::comment_export" {
  let ast = try! parse(parser_upstream_source("export x := y # foo\n"))
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  assert_true(assignment.exported())
  guard ast.items()[1] is TrailingComment(text~, ..) else {
    fail("expected trailing comment")
  }
  assert_eq(text, "# foo")
}

///|
test "upstream parser::tests::comment_recipe" {
  let ast = try! parse(parser_upstream_source("foo: # bar\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.name(), "foo")
  assert_eq(recipe.trailing_comment().unwrap(), "# bar")
}

///|
test "upstream parser::tests::comment_recipe_dependencies" {
  let ast = try! parse(parser_upstream_source("foo: bar # baz\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.dependencies().length(), 1)
  assert_eq(recipe.dependencies()[0].name(), "bar")
  assert_eq(recipe.trailing_comment().unwrap(), "# baz")
}

///|
test "upstream parser::tests::parse_alias_with_comment" {
  let ast = try! parse(
    parser_upstream_source("alias f := foo # comment\nfoo:\n echo a\n"),
  )
  guard ast.items()[0] is Alias(alias_item) else { fail("expected alias") }
  guard ast.items()[1] is TrailingComment(text~, ..) else {
    fail("expected trailing comment")
  }
  assert_eq(alias_item.target(), "foo")
  assert_eq(text, "# comment")
}

///|
test "upstream parser::tests::parse_assignment_with_comment" {
  let ast = try! parse(
    parser_upstream_source("f := foo # comment\nfoo:\n echo a\n"),
  )
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  guard ast.items()[1] is TrailingComment(text~, ..) else {
    fail("expected trailing comment")
  }
  assert_eq(assignment.name(), "f")
  assert_eq(text, "# comment")
}

///|
test "upstream parser::tests::doc_comment_single" {
  let ast = try! parse(parser_upstream_source("# foo\nbar:\n"))
  guard ast.items()[0] is Comment(text~, ..) else { fail("expected comment") }
  guard ast.items()[1] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(text, "# foo")
  assert_eq(recipe.name(), "bar")
}

///|
test "upstream parser::tests::doc_comment_assignment_clear" {
  let ast = try! parse(parser_upstream_source("# foo\nx := y\nbar:\n"))
  assert_eq(
    ast.semantic_key(),
    "comment:# foo\nassignment:x:false:false:var:y:attrs[]\nrecipe:bar:false:params[]:deps[]:subseq[]:lines[]:attrs[]",
  )
}

///|
test "upstream parser::tests::doc_comment_empty_line_clear" {
  let ast = try! parse(parser_upstream_source("# foo\n\nbar:\n"))
  assert_eq(
    ast.semantic_key(),
    "comment:# foo\nblank\nrecipe:bar:false:params[]:deps[]:subseq[]:lines[]:attrs[]",
  )
}

///|
test "upstream parser::tests::doc_comment_middle" {
  let ast = try! parse(parser_upstream_source("bar:\n# foo\nbaz:\n"))
  assert_eq(
    ast.semantic_key(),
    "recipe:bar:false:params[]:deps[]:subseq[]:lines[]:attrs[]\ncomment:# foo\nrecipe:baz:false:params[]:deps[]:subseq[]:lines[]:attrs[]",
  )
}

///|
test "upstream parser::tests::doc_comment_recipe_clear" {
  let ast = try! parse(parser_upstream_source("# foo\nbar:\nbaz:\n"))
  assert_eq(
    ast.semantic_key(),
    "comment:# foo\nrecipe:bar:false:params[]:deps[]:subseq[]:lines[]:attrs[]\nrecipe:baz:false:params[]:deps[]:subseq[]:lines[]:attrs[]",
  )
}

///|
test "upstream justfile::tests::parse_alias_with_comment" {
  let ast = try! parse(
    parser_upstream_source("alias f := foo # comment\nfoo:\n echo a\n"),
  )
  guard ast.items()[1] is TrailingComment(text~, ..) else {
    fail("expected comment")
  }
  assert_eq(text, "# comment")
}
