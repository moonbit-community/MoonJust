///|
test "upstream parser::tests::set_allow_duplicate_recipes_implicit" {
  let ast = try! parse(parser_upstream_source("set allow-duplicate-recipes\n"))
  assert_eq(ast.semantic_key(), "setting:allow-duplicate-recipes=")
}

///|
test "upstream parser::tests::set_allow_duplicate_variables_implicit" {
  let ast = try! parse(
    parser_upstream_source("set allow-duplicate-variables\n"),
  )
  assert_eq(ast.semantic_key(), "setting:allow-duplicate-variables=")
}

///|
test "upstream parser::tests::set_dotenv_load_implicit" {
  let ast = try! parse(parser_upstream_source("set dotenv-load\n"))
  assert_eq(ast.semantic_key(), "setting:dotenv-load=")
}

///|
test "upstream parser::tests::set_export_true" {
  let ast = try! parse(parser_upstream_source("set export := true\n"))
  assert_eq(ast.semantic_key(), "setting:export=bool:true")
}

///|
test "upstream parser::tests::set_positional_arguments_false" {
  let ast = try! parse(
    parser_upstream_source("set positional-arguments := false\n"),
  )
  assert_eq(ast.semantic_key(), "setting:positional-arguments=bool:false")
}

///|
test "upstream parser::tests::set_positional_arguments_implicit" {
  let ast = try! parse(parser_upstream_source("set positional-arguments\n"))
  assert_eq(ast.semantic_key(), "setting:positional-arguments=")
}

///|
test "upstream parser::tests::set_quiet_false" {
  let ast = try! parse(parser_upstream_source("set quiet := false\n"))
  assert_eq(ast.semantic_key(), "setting:quiet=bool:false")
}

///|
test "upstream parser::tests::set_windows_powershell_false" {
  let ast = try! parse(
    parser_upstream_source("set windows-powershell := false\n"),
  )
  assert_eq(ast.semantic_key(), "setting:windows-powershell=bool:false")
}

///|
test "upstream parser::tests::set_windows_powershell_implicit" {
  let ast = try! parse(parser_upstream_source("set windows-powershell\n"))
  assert_eq(ast.semantic_key(), "setting:windows-powershell=")
}

///|
test "upstream parser::tests::set_windows_powershell_true" {
  let ast = try! parse(
    parser_upstream_source("set windows-powershell := true\n"),
  )
  assert_eq(ast.semantic_key(), "setting:windows-powershell=bool:true")
}

///|
test "upstream parser::tests::set_shell_no_arguments" {
  let ast = try! parse(parser_upstream_source("set shell := ['tclsh']\n"))
  guard ast.items()[0] is Setting(setting) else { fail("expected setting") }
  assert_eq(setting.name(), "shell")
  assert_eq(setting.value().unwrap().semantic_key(), "list:[string:raw(tclsh)]")
}

///|
test "upstream parser::tests::set_shell_with_one_argument" {
  let ast = try! parse(parser_upstream_source("set shell := ['bash', '-cu']\n"))
  guard ast.items()[0] is Setting(setting) else { fail("expected setting") }
  assert_eq(
    setting.value().unwrap().semantic_key(),
    "list:[string:raw(bash),string:raw(-cu)]",
  )
}

///|
test "upstream parser::tests::set_shell_with_two_arguments" {
  let ast = try! parse(
    parser_upstream_source("set shell := ['bash', '-cu', '-l']\n"),
  )
  guard ast.items()[0] is Setting(setting) else { fail("expected setting") }
  assert_eq(
    setting.value().unwrap().semantic_key(),
    "list:[string:raw(bash),string:raw(-cu),string:raw(-l)]",
  )
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
test "upstream parser::tests::format_string_expression" {
  let ast = try! parse(
    parser_upstream_source("foo := f'foo{{ 'abc' + 'xyz' }}bar'\n"),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:foo:false:false:format:raw(foo)[binary:concat(string:raw(abc),string:raw(xyz))=>raw(bar)]:attrs[]",
  )
}

///|
test "upstream parser::tests::format_string_complex" {
  let ast = try! parse(
    parser_upstream_source(
      "foo := f'foo{{ 'abc' + 'xyz' }}bar{{ 'hello' }}goodbye'\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:foo:false:false:format:raw(foo)[binary:concat(string:raw(abc),string:raw(xyz))=>raw(bar),string:raw(hello)=>raw(goodbye)]:attrs[]",
  )
}

///|
test "upstream parser::tests::env_functions" {
  let ast = try! parse(
    parser_upstream_source(
      "x := env_var('foo',)\n\na:\n {{env_var_or_default('foo' + 'bar', 'baz',)}} {{env_var(env_var('baz'))}}\n",
    ),
  )
  assert_eq(
    ast
    .items()
    .filter_map(fn(item) {
      match item {
        Assignment(_) | Recipe(_) => Some(())
        _ => None
      }
    })
    .length(),
    2,
  )
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  assert_eq(assignment.value().kind(), "call")
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
test "upstream parser::tests::unary_functions" {
  let ast = try! parse(
    parser_upstream_source("x := arch()\n\na:\n {{os()}} {{os_family()}}\n"),
  )
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  assert_eq(assignment.value().kind(), "call")
  let recipe = ast
    .items()
    .filter_map(fn(item) {
      match item {
        Recipe(recipe) => Some(recipe)
        _ => None
      }
    })[0]
  assert_eq(recipe.lines()[0].fragments().length(), 3)
}

///|
test "upstream parser::tests::whitespace" {
  let ast = try! parse(parser_upstream_source(" "))
  assert_true(ast.items().is_empty())
}

///|
test "upstream parser::tests::doc_comment_single" {
  let ast = try! parse(parser_upstream_source("# foo\nbar:\n"))
  guard ast.items()[0] is Comment(text~, ..) else { fail("expected comment") }
  guard ast.items()[1] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(text, "# foo")
  assert_eq(recipe.name(), "bar")
}
