///|
test "upstream parser::tests::recipe_default_single" {
  let ast = try! parse(parser_upstream_source("foo bar='baz':\n"))
  assert_eq(
    ast.semantic_key(),
    "recipe:foo:false:params[bar:false:0:false:string:raw(baz)]:deps[]:subseq[]:lines[]:attrs[]",
  )
}

///|
test "upstream parser::tests::recipe_default_multiple" {
  let ast = try! parse(parser_upstream_source("foo bar='baz' bob='biz':\n"))
  assert_eq(
    ast.semantic_key(),
    "recipe:foo:false:params[bar:false:0:false:string:raw(baz),bob:false:0:false:string:raw(biz)]:deps[]:subseq[]:lines[]:attrs[]",
  )
}

///|
test "upstream parser::tests::recipe_parameter_multiple" {
  let ast = try! parse(parser_upstream_source("foo bar baz:\n"))
  assert_eq(
    ast.semantic_key(),
    "recipe:foo:false:params[bar:false:0:false:,baz:false:0:false:]:deps[]:subseq[]:lines[]:attrs[]",
  )
}

///|
test "upstream parser::tests::recipe_parameter_single" {
  let ast = try! parse(parser_upstream_source("foo bar:\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.parameters().length(), 1)
  assert_eq(recipe.parameters()[0].name(), "bar")
  assert_true(!recipe.parameters()[0].variadic())
}

///|
test "upstream parser::tests::recipe_plus_variadic" {
  let ast = try! parse(parser_upstream_source("foo +bar:\n"))
  assert_eq(
    ast.semantic_key(),
    "recipe:foo:false:params[bar:true:1:false:]:deps[]:subseq[]:lines[]:attrs[]",
  )
}

///|
test "upstream parser::tests::recipe_star_variadic" {
  let ast = try! parse(parser_upstream_source("foo *bar:\n"))
  assert_eq(
    ast.semantic_key(),
    "recipe:foo:false:params[bar:true:0:false:]:deps[]:subseq[]:lines[]:attrs[]",
  )
}

///|
test "upstream parser::tests::parameters" {
  let ast = try! parse(parser_upstream_source("a b c:\n {{b}} {{c}}\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.parameters().length(), 2)
  assert_eq(recipe.parameters()[0].name(), "b")
  assert_eq(recipe.parameters()[1].name(), "c")
  assert_eq(recipe.lines()[0].fragments().length(), 3)
}

///|
test "upstream parser::tests::recipe_variadic_string_default" {
  let ast = try! parse(parser_upstream_source("foo +bar='baz':\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  let parameter = recipe.parameters()[0]
  assert_true(parameter.variadic())
  assert_eq(parameter.variadic_minimum(), 1)
  assert_eq(
    parameter.default_value().unwrap().semantic_key(),
    "string:raw(baz)",
  )
}

///|
test "upstream parser::tests::recipe_variadic_variable_default" {
  let ast = try! parse(parser_upstream_source("foo +bar=baz:\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "var:baz",
  )
}

///|
test "upstream parser::tests::recipe_variadic_addition_group_default" {
  let ast = try! parse(parser_upstream_source("foo +bar=(baz + bob):\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "parenthesized:(binary:concat(var:baz,var:bob))",
  )
}

///|
test "upstream parser::tests::recipe_variadic_with_default_after_default" {
  let ast = try! parse(parser_upstream_source("f a=b +c=d:\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.parameters().length(), 2)
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "var:b",
  )
  assert_eq(recipe.parameters()[1].variadic_minimum(), 1)
}

///|
test "upstream parser::tests::parameter_default_backtick" {
  let ast = try! parse(parser_upstream_source("f x=`echo hello`:\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "backtick:backtick(echo hello)",
  )
}

///|
test "upstream parser::tests::parameter_default_string" {
  let ast = try! parse(parser_upstream_source("f x='abc':\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "string:raw(abc)",
  )
}

///|
test "upstream parser::tests::parameter_default_concatenation_string" {
  let ast = try! parse(parser_upstream_source("f x=(`echo hello` + 'foo'):\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "parenthesized:(binary:concat(backtick:backtick(echo hello),string:raw(foo)))",
  )
}

///|
test "upstream parser::tests::parameter_default_raw_string" {
  let ast = try! parse(parser_upstream_source("f x='abc':\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.parameters()[0].default_value().unwrap().kind(), "string")
}

///|
test "upstream parser::tests::parameter_after_variadic" {
  let source = parser_upstream_source("foo +a bbb:")
  try parse(source) catch {
    error => {
      assert_eq(error.span().start_byte(), 7)
      assert_eq(error.span().length(), 3)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::parameter_follows_variadic_parameter" {
  let source = parser_upstream_source("foo +a b:")
  try parse(source) catch {
    error => {
      assert_eq(error.span().start_byte(), 7)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::parse_raw_string_default" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(896),
      "justfile",
      "foo a='b\\t':\n",
    ),
  )
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "string:raw(b\\t)",
  )
}

///|
test "upstream parser::tests::parameter_default_concatenation_variable" {
  let ast = try! parse(
    parser_upstream_source("x := '10'\nf y=(`echo hello` + x) +z='foo':\n"),
  )
  guard ast.items()[1] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.name(), "f")
  assert_eq(recipe.parameters().length(), 2)
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "parenthesized:(binary:concat(backtick:backtick(echo hello),var:x))",
  )
  assert_true(recipe.parameters()[1].variadic())
  assert_eq(
    recipe.parameters()[1].default_value().unwrap().semantic_key(),
    "string:raw(foo)",
  )
}

///|
test "upstream parser::tests::parameter_default_multiple" {
  let ast = try! parse(
    parser_upstream_source(
      "x := '10'\nf y=(`echo hello` + x) +z=('foo' + 'bar'):\n",
    ),
  )
  guard ast.items()[1] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "parenthesized:(binary:concat(backtick:backtick(echo hello),var:x))",
  )
  assert_eq(
    recipe.parameters()[1].default_value().unwrap().semantic_key(),
    "parenthesized:(binary:concat(string:raw(foo),string:raw(bar)))",
  )
}

///|
test "upstream justfile::tests::parse_string_default" {
  let ast = try! parse(parser_upstream_source("foo x='abc':\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "string:raw(abc)",
  )
}

///|
test "upstream justfile::tests::parse_raw_string_default" {
  let ast = try! parse(parser_upstream_source("foo x='abc':\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.parameters()[0].default_value().unwrap().kind(), "string")
}

///|
test "upstream justfile::tests::parse_variadic" {
  let ast = try! parse(parser_upstream_source("foo +bar:\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_true(recipe.parameters()[0].variadic())
}

///|
test "upstream justfile::tests::parse_variadic_string_default" {
  let ast = try! parse(parser_upstream_source("foo +bar='baz':\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "string:raw(baz)",
  )
  assert_eq(recipe.parameters()[0].variadic_minimum(), 1)
}

///|
test "upstream justfile::tests::parameter_default_backtick" {
  let ast = try! parse(parser_upstream_source("f x=`echo hello`:\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "backtick:backtick(echo hello)",
  )
}

///|
test "upstream justfile::tests::parameter_default_concatenation_string" {
  let ast = try! parse(parser_upstream_source("f x=(`echo hello` + 'foo'):\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_true(
    recipe.parameters()[0].default_value().unwrap().kind() == "parenthesized",
  )
}

///|
test "upstream justfile::tests::parameter_default_concatenation_variable" {
  let ast = try! parse(parser_upstream_source("f x=(a + b):\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "parenthesized:(binary:concat(var:a,var:b))",
  )
}

///|
test "upstream justfile::tests::parameter_default_multiple" {
  let ast = try! parse(parser_upstream_source("f a='x' b='y':\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.parameters().length(), 2)
}

///|
test "upstream justfile::tests::parameters" {
  let ast = try! parse(parser_upstream_source("a b c:\n {{b}} {{c}}\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.parameters().map(fn(parameter) { parameter.name() }), [
    "b", "c",
  ])
}

///|
test "upstream justfile::tests::parameter_default_string" {
  let ast = try! parse(parser_upstream_source("foo x='abc':\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "string:raw(abc)",
  )
}

///|
test "upstream justfile::tests::parameter_default_raw_string" {
  let ast = try! parse(parser_upstream_source("foo x='abc':\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.parameters()[0].default_value().unwrap().kind(), "string")
}
