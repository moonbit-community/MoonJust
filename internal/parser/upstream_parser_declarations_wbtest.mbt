///|
test "upstream parser::tests::alias_modulepath" {
  let ast = try! parse(parser_upstream_source("alias fbb := foo::bar::baz\n"))
  guard ast.items()[0] is Alias(alias_item) else { fail("expected alias") }
  assert_eq(alias_item.name(), "fbb")
  assert_eq(alias_item.target(), "foo::bar::baz")
}

///|
test "upstream parser::tests::aliases_multiple" {
  let ast = try! parse(
    parser_upstream_source("alias t := test\nalias b := build\n"),
  )
  guard ast.items()[0] is Alias(first) else { fail("expected first alias") }
  guard ast.items()[1] is Alias(second) else { fail("expected second alias") }
  assert_eq(first.name(), "t")
  assert_eq(first.target(), "test")
  assert_eq(second.name(), "b")
  assert_eq(second.target(), "build")
}

///|
test "upstream parser::tests::assignment_equals" {
  let ast = try! parse(parser_upstream_source("x := 'hello'\n"))
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  assert_eq(assignment.name(), "x")
  assert_eq(assignment.value().kind(), "string")
  assert_eq(assignment.value().semantic_key(), "string:raw(hello)")
}

///|
test "upstream parser::tests::export_equals" {
  let ast = try! parse(parser_upstream_source("export x := 'hello'\n"))
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  assert_true(assignment.exported())
  assert_eq(assignment.name(), "x")
}

///|
test "upstream parser::tests::module_with" {
  let ast = try! parse(parser_upstream_source("mod foo\n"))
  guard ast.items()[0] is Module(module_item) else { fail("expected module") }
  assert_eq(module_item.name(), "foo")
  assert_true(!module_item.optional())
  assert_true(module_item.path() is None)
}

///|
test "upstream parser::tests::module_with_path" {
  let ast = try! parse(
    parser_upstream_source("mod foo \"some/file/path.txt\"\n"),
  )
  guard ast.items()[0] is Module(module_item) else { fail("expected module") }
  assert_eq(module_item.name(), "foo")
  assert_eq(module_item.path().unwrap().cooked(), "some/file/path.txt")
}

///|
test "upstream parser::tests::optional_module" {
  let ast = try! parse(parser_upstream_source("mod? foo\n"))
  guard ast.items()[0] is Module(module_item) else { fail("expected module") }
  assert_eq(module_item.name(), "foo")
  assert_true(module_item.optional())
}

///|
test "upstream parser::tests::optional_module_with_path" {
  let ast = try! parse(
    parser_upstream_source("mod? foo \"some/file/path.txt\"\n"),
  )
  guard ast.items()[0] is Module(module_item) else { fail("expected module") }
  assert_true(module_item.optional())
  assert_eq(module_item.path().unwrap().cooked(), "some/file/path.txt")
}

///|
test "upstream parser::tests::parse_assignments" {
  let ast = try! parse(
    parser_upstream_source("a := '0'\nc := a + b + a + b\nb := '1'\n"),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:string:raw(0):attrs[]\nassignment:c:false:false:binary:concat(var:a,binary:concat(var:b,binary:concat(var:a,var:b))):attrs[]\nassignment:b:false:false:string:raw(1):attrs[]",
  )
}

///|
test "upstream parser::tests::parse_assignment_backticks" {
  let ast = try! parse(
    parser_upstream_source(
      "a := `echo hello`\nc := a + b + a + b\nb := `echo goodbye`\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:backtick:backtick(echo hello):attrs[]\nassignment:c:false:false:binary:concat(var:a,binary:concat(var:b,binary:concat(var:a,var:b))):attrs[]\nassignment:b:false:false:backtick:backtick(echo goodbye):attrs[]",
  )
}

///|
test "upstream parser::tests::private_assignment" {
  let ast = try! parse(parser_upstream_source("[private]\nx := 'hello'\n"))
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  assert_eq(assignment.attributes().length(), 1)
  assert_eq(assignment.attributes()[0].name(), "private")
}

///|
test "upstream parser::tests::private_export" {
  let ast = try! parse(
    parser_upstream_source("[private]\nexport x := 'hello'\n"),
  )
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  assert_true(assignment.exported())
  assert_eq(assignment.attributes()[0].name(), "private")
}

///|
test "upstream parser::tests::parse_alias_before_target" {
  let ast = try! parse(
    parser_upstream_source("alias f := foo\nfoo:\n echo a\n"),
  )
  guard ast.items()[0] is Alias(alias_item) else { fail("expected alias") }
  guard ast.items()[1] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(alias_item.target(), "foo")
  assert_eq(recipe.name(), "foo")
}

///|
test "upstream parser::tests::parse_alias_after_target" {
  let ast = try! parse(
    parser_upstream_source("foo:\n echo a\nalias f := foo\n"),
  )
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  guard ast.items()[1] is Alias(alias_item) else { fail("expected alias") }
  assert_eq(recipe.name(), "foo")
  assert_eq(alias_item.name(), "f")
}

///|
test "upstream parser::tests::alias_with_attribute" {
  let ast = try! parse(parser_upstream_source("[private]\nalias t := test"))
  guard ast.items()[0] is Alias(alias_item) else { fail("expected alias") }
  assert_eq(alias_item.name(), "t")
  assert_eq(alias_item.target(), "test")
  assert_eq(alias_item.attributes().length(), 1)
  assert_eq(alias_item.attributes()[0].name(), "private")
}

///|
test "upstream parser::tests::recipe_named_alias" {
  let ast = try! parse(
    parser_upstream_source("[private]\nalias:\n  echo 'echoing alias'\n"),
  )
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.name(), "alias")
  assert_eq(recipe.attributes().length(), 1)
  assert_eq(recipe.attributes()[0].name(), "private")
  assert_eq(recipe.lines().length(), 1)
  guard recipe.lines()[0].fragments()[0] is Text(text~, ..) else {
    fail("expected text fragment")
  }
  assert_eq(text, "echo 'echoing alias'")
}

///|
test "upstream parser::tests::single_argument_attribute_shorthand" {
  let ast = try! parse(parser_upstream_source("[group: 'foo']\nbar:"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.attributes().length(), 1)
  assert_eq(recipe.attributes()[0].name(), "group")
  assert_eq(
    recipe.attributes()[0].arguments()[0].value().unwrap().semantic_key(),
    "string:raw(foo)",
  )
}

///|
test "upstream parser::tests::single_argument_attribute_shorthand_multiple_same_line" {
  let ast = try! parse(
    parser_upstream_source("[group: 'foo', group: 'bar']\nbaz:"),
  )
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.attributes().length(), 2)
  assert_eq(
    recipe.attributes()[0].arguments()[0].value().unwrap().semantic_key(),
    "string:raw(foo)",
  )
  assert_eq(
    recipe.attributes()[1].arguments()[0].value().unwrap().semantic_key(),
    "string:raw(bar)",
  )
}

///|
test "upstream justfile::tests::parse_alias_before_target" {
  let ast = try! parse(
    parser_upstream_source("alias f := foo\nfoo:\n echo a\n"),
  )
  guard ast.items()[0] is Alias(alias_item) else { fail("expected alias") }
  assert_eq(alias_item.target(), "foo")
}

///|
test "upstream justfile::tests::parse_alias_after_target" {
  let ast = try! parse(
    parser_upstream_source("foo:\n echo a\nalias f := foo\n"),
  )
  guard ast.items()[1] is Alias(alias_item) else { fail("expected alias") }
  assert_eq(alias_item.name(), "f")
}

///|
test "upstream justfile::tests::parse_assignments" {
  let ast = try! parse(
    parser_upstream_source("a := '0'\nc := a + b + a + b\nb := '1'\n"),
  )
  assert_eq(ast.items().length(), 3)
  assert_eq(
    ast.items()[1].semantic_key(),
    "assignment:c:false:false:binary:concat(var:a,binary:concat(var:b,binary:concat(var:a,var:b))):attrs[]",
  )
}

///|
test "upstream justfile::tests::parse_assignment_backticks" {
  let ast = try! parse(
    parser_upstream_source(
      "a := `echo hello`\nc := a + b + a + b\nb := `echo goodbye`\n",
    ),
  )
  assert_eq(
    ast.items()[0].semantic_key(),
    "assignment:a:false:false:backtick:backtick(echo hello):attrs[]",
  )
}
