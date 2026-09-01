///|
fn parser_upstream_source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(891), "justfile", text)
}

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
test "upstream parser::tests::assert" {
  let ast = try! parse(parser_upstream_source("a := assert(b, \"error\")\n"))
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:call:assert[var:b,string:cooked(error)]:attrs[]",
  )
}

///|
test "upstream parser::tests::assert_conditional_condition" {
  let ast = try! parse(
    parser_upstream_source("foo := assert(if a { b } else { c }, \"error\")\n"),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:foo:false:false:call:assert[if(var:a,var:b,var:c),string:cooked(error)]:attrs[]",
  )
}

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
test "upstream parser::tests::concatenation_in_group" {
  let ast = try! parse(parser_upstream_source("x := ('0' + '1')\n"))
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:parenthesized:(binary:concat(string:raw(0),string:raw(1))):attrs[]",
  )
}

///|
test "upstream parser::tests::conditional_without_otherwise" {
  let ast = try! parse(parser_upstream_source("a := if b { c }\n"))
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:if(var:b,var:c,):attrs[]",
  )
}

///|
test "upstream parser::tests::empty_multiline" {
  let ast = try! parse(parser_upstream_source("\n\n\n"))
  assert_true(ast.items().all(fn(item) { item is Blank(..) }))
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
test "upstream parser::tests::list_concatenation_single" {
  let ast = try! parse(parser_upstream_source("x := a ++ b\n"))
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:binary:list-concat(var:a,var:b):attrs[]",
  )
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
test "upstream parser::tests::recipe_quiet" {
  let ast = try! parse(parser_upstream_source("@foo:\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.name(), "foo")
  assert_true(recipe.quiet())
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
test "upstream parser::tests::recipe_subsequent" {
  let ast = try! parse(parser_upstream_source("foo: && bar\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.subsequent_dependencies().length(), 1)
  assert_eq(recipe.subsequent_dependencies()[0].name(), "bar")
}

///|
test "upstream parser::tests::set_export_implicit" {
  let ast = try! parse(parser_upstream_source("set export\n"))
  assert_eq(ast.semantic_key(), "setting:export=")
}

///|
test "upstream parser::tests::set_export_false" {
  let ast = try! parse(parser_upstream_source("set export := false\n"))
  assert_eq(ast.semantic_key(), "setting:export=bool:false")
}

///|
test "upstream parser::tests::set_quiet_implicit" {
  let ast = try! parse(parser_upstream_source("set quiet\n"))
  assert_eq(ast.semantic_key(), "setting:quiet=")
}

///|
test "upstream parser::tests::set_quiet_true" {
  let ast = try! parse(parser_upstream_source("set quiet := true\n"))
  assert_eq(ast.semantic_key(), "setting:quiet=bool:true")
}

///|
test "upstream parser::tests::set_working_directory" {
  let ast = try! parse(
    parser_upstream_source("set working-directory := 'foo'\n"),
  )
  assert_eq(ast.semantic_key(), "setting:working-directory=string:raw(foo)")
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
test "upstream parser::tests::recipe_line_interpolation" {
  let ast = try! parse(parser_upstream_source("foo:\n bar{{\"bob\"}}biz\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  guard recipe.lines()[0].fragments()[0] is Text(text~, ..) else {
    fail("expected leading text")
  }
  assert_eq(text, "bar")
  guard recipe.lines()[0].fragments()[1] is Interpolation(expression~, ..) else {
    fail("expected interpolation")
  }
  assert_eq(expression.semantic_key(), "string:cooked(bob)")
  guard recipe.lines()[0].fragments()[2] is Text(text~, ..) else {
    fail("expected trailing text")
  }
  assert_eq(text, "biz")
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
test "upstream parser::tests::string_in_group" {
  let ast = try! parse(parser_upstream_source("x := ('0'   )\n"))
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:parenthesized:(string:raw(0)):attrs[]",
  )
}

///|
test "upstream parser::tests::format_string_simple" {
  let ast = try! parse(parser_upstream_source("foo := f'abc'\n"))
  assert_eq(
    ast.semantic_key(),
    "assignment:foo:false:false:format:raw(abc)[]:attrs[]",
  )
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
test "upstream parser::tests::set_dotenv_load_true" {
  let ast = try! parse(parser_upstream_source("set dotenv-load := true\n"))
  assert_eq(ast.semantic_key(), "setting:dotenv-load=bool:true")
}

///|
test "upstream parser::tests::set_dotenv_load_false" {
  let ast = try! parse(parser_upstream_source("set dotenv-load := false\n"))
  assert_eq(ast.semantic_key(), "setting:dotenv-load=bool:false")
}

///|
test "upstream parser::tests::set_positional_arguments_true" {
  let ast = try! parse(
    parser_upstream_source("set positional-arguments := true\n"),
  )
  assert_eq(ast.semantic_key(), "setting:positional-arguments=bool:true")
}

///|
test "upstream parser::tests::set_no_cd" {
  let ast = try! parse(parser_upstream_source("set no-cd := true\n"))
  assert_eq(ast.semantic_key(), "setting:no-cd=bool:true")
}
