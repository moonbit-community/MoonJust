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
test "upstream parser::tests::set_shell_no_arguments_trailing_comma" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(892),
      "justfile",
      "set shell := ['tclsh',]\n",
    ),
  )
  guard ast.items()[0] is Setting(setting) else { fail("expected setting") }
  assert_eq(setting.name(), "shell")
  assert_eq(setting.value().unwrap().semantic_key(), "list:[string:raw(tclsh)]")
}

///|
test "upstream parser::tests::set_shell_with_one_argument_trailing_comma" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(893),
      "justfile",
      "set shell := ['bash', '-cu',]\n",
    ),
  )
  guard ast.items()[0] is Setting(setting) else { fail("expected setting") }
  assert_eq(setting.name(), "shell")
  assert_eq(
    setting.value().unwrap().semantic_key(),
    "list:[string:raw(bash),string:raw(-cu)]",
  )
}

///|
test "upstream parser::tests::indented_string_raw_with_dedent" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(894),
      "justfile",
      "x := '''\n  foo\\t\n  bar\\n\n'''\n",
    ),
  )
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  guard assignment.value() is String(literal) else {
    fail("expected string literal")
  }
  assert_eq(literal.cooked(), "foo\\t\nbar\\n\n")
}

///|
test "upstream parser::tests::indented_string_raw_no_dedent" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(895),
      "justfile",
      "x := '''\nfoo\\t\n  bar\\n\n'''\n",
    ),
  )
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  guard assignment.value() is String(literal) else {
    fail("expected string literal")
  }
  assert_eq(literal.cooked(), "foo\\t\n  bar\\n\n")
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
test "upstream slash_operator::no_rhs_once" {
  let source = @source.Source::from_text(
    @source.SourceId::new(899),
    "justfile",
    "x := 'a' /",
  )
  try parse(source) catch {
    error =>
      match error {
        UnexpectedToken(found=Eof, span~, ..) => {
          assert_eq(span.start_byte(), 10)
          assert_eq(span.length(), 0)
        }
        _ => fail("unexpected parser error")
      }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
fn parser_remaining_source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(927), "justfile", text)
}

///|
test "upstream parser::tests::alias_with_attribute" {
  let ast = try! parse(parser_remaining_source("[private]\nalias t := test"))
  guard ast.items()[0] is Alias(alias_item) else { fail("expected alias") }
  assert_eq(alias_item.name(), "t")
  assert_eq(alias_item.target(), "test")
  assert_eq(alias_item.attributes().length(), 1)
  assert_eq(alias_item.attributes()[0].name(), "private")
}

///|
test "upstream parser::tests::set_shell_no_arguments_cooked" {
  let ast = try! parse(parser_remaining_source("set shell := [\"tclsh\"]"))
  guard ast.items()[0] is Setting(setting) else { fail("expected setting") }
  assert_eq(setting.name(), "shell")
  assert_eq(
    setting.value().unwrap().semantic_key(),
    "list:[string:cooked(tclsh)]",
  )
}

///|
test "upstream parser::tests::recipe_named_alias" {
  let ast = try! parse(
    parser_remaining_source("[private]\nalias:\n  echo 'echoing alias'\n"),
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
  let ast = try! parse(parser_remaining_source("[group: 'foo']\nbar:"))
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
    parser_remaining_source("[group: 'foo', group: 'bar']\nbaz:"),
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
test "upstream parser::tests::indented_string_cooked" {
  let ast = try! parse(
    parser_remaining_source("x := \"\"\"\n  \\tfoo\\t\n  \\tbar\\n\n\"\"\"\n"),
  )
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  guard assignment.value() is String(literal) else {
    fail("expected string literal")
  }
  assert_eq(literal.cooked(), "\tfoo\t\n\tbar\n\n")
}

///|
test "upstream parser::tests::indented_string_cooked_no_dedent" {
  let ast = try! parse(
    parser_remaining_source("x := \"\"\"\n\\tfoo\\t\n  \\tbar\\n\n\"\"\"\n"),
  )
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  guard assignment.value() is String(literal) else {
    fail("expected string literal")
  }
  assert_eq(literal.cooked(), "\tfoo\t\n  \tbar\n\n")
}

///|
test "upstream parser::tests::indented_backtick" {
  let ast = try! parse(
    parser_remaining_source("x := ```\n  \\tfoo\\t\n  \\tbar\\n\n```\n"),
  )
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  guard assignment.value() is Backtick(value) else { fail("expected backtick") }
  assert_eq(value.cooked(), "\\tfoo\\t\n\\tbar\\n\n")
}

///|
test "upstream parser::tests::indented_backtick_no_dedent" {
  let ast = try! parse(
    parser_remaining_source("x := ```\n\\tfoo\\t\n  \\tbar\\n\n```\n"),
  )
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  guard assignment.value() is Backtick(value) else { fail("expected backtick") }
  assert_eq(value.cooked(), "\\tfoo\\t\n  \\tbar\\n\n")
}

///|
test "upstream parser::tests::parse_interpolation_backticks" {
  let ast = try! parse(
    parser_remaining_source(
      "a:\n  echo {{  `echo hello` + 'blarg'   }} {{   `echo bob`   }}\n",
    ),
  )
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.lines().length(), 1)
  let fragments = recipe.lines()[0].fragments()
  assert_eq(fragments.length(), 4)
  guard fragments[0] is Text(text~, ..) else { fail("expected text") }
  assert_eq(text, "echo ")
  guard fragments[1] is Interpolation(expression~, ..) else {
    fail("expected interpolation")
  }
  assert_eq(
    expression.semantic_key(),
    "binary:concat(backtick:backtick(echo hello),string:raw(blarg))",
  )
  guard fragments[2] is Text(text~, ..) else { fail("expected text") }
  assert_eq(text, " ")
  guard fragments[3] is Interpolation(expression~, ..) else {
    fail("expected interpolation")
  }
  assert_eq(expression.semantic_key(), "backtick:backtick(echo bob)")
}

///|
test "upstream parser::tests::parameter_default_concatenation_variable" {
  let ast = try! parse(
    parser_remaining_source("x := '10'\nf y=(`echo hello` + x) +z='foo':\n"),
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
    parser_remaining_source(
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
test "upstream string::indented_backtick_string_escapes" {
  let ast = try! parse(
    parser_remaining_source(
      "a := ```\n  printf %s '\n  foo\\n\n  bar\n  '\n```\n",
    ),
  )
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  guard assignment.value() is Backtick(value) else { fail("expected backtick") }
  assert_eq(value.cooked(), "printf %s '\nfoo\\n\nbar\n'\n")
}

///|
test "upstream string::indented_raw_string_escapes" {
  let ast = try! parse(
    parser_remaining_source("a := '''\n  foo\\n\n  bar\n'''\n"),
  )
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  guard assignment.value() is String(value) else {
    fail("expected string literal")
  }
  assert_eq(value.cooked(), "foo\\n\nbar\n")
}

///|
test "upstream string::indented_string_crlf_blank_lines_keep_crlf" {
  let ast = try! parse(
    parser_remaining_source("x := '''\r\nfoo\r\n\r\nbar\r\n'''\r\n"),
  )
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  guard assignment.value() is String(value) else {
    fail("expected string literal")
  }
  assert_eq(value.cooked(), "foo\r\n\r\nbar\r\n")
}

///|
test "upstream parser::tests::escaped_dos_newlines" {
  let ast = try! parse(
    parser_remaining_source(
      "@spam:\r\n\t{ \\\r\n\t\tfiglet test; \\\r\n\t\tcargo build --color always 2>&1; \\\r\n\t\tcargo test  --color always -- --color always 2>&1; \\\r\n\t} | less\r\n",
    ),
  )
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.name(), "spam")
  assert_true(recipe.quiet())
  assert_eq(recipe.lines().length(), 5)
  let expected = [
    "{ \\", "\tfiglet test; \\", "\tcargo build --color always 2>&1; \\", "\tcargo test  --color always -- --color always 2>&1; \\",
    "} | less",
  ]
  for index, line in recipe.lines() {
    guard line.fragments()[0] is Text(text~, ..) else {
      fail("expected text fragment")
    }
    assert_eq(text, expected[index])
  }
}

///|
test "upstream parser::tests::doc_comment_assignment_clear" {
  let ast = try! parse(parser_remaining_source("# foo\nx := y\nbar:\n"))
  assert_eq(
    ast.semantic_key(),
    "comment:# foo\nassignment:x:false:false:var:y:attrs[]\nrecipe:bar:false:params[]:deps[]:subseq[]:lines[]:attrs[]",
  )
}

///|
test "upstream parser::tests::doc_comment_empty_line_clear" {
  let ast = try! parse(parser_remaining_source("# foo\n\nbar:\n"))
  assert_eq(
    ast.semantic_key(),
    "comment:# foo\nblank\nrecipe:bar:false:params[]:deps[]:subseq[]:lines[]:attrs[]",
  )
}

///|
test "upstream parser::tests::doc_comment_middle" {
  let ast = try! parse(parser_remaining_source("bar:\n# foo\nbaz:\n"))
  assert_eq(
    ast.semantic_key(),
    "recipe:bar:false:params[]:deps[]:subseq[]:lines[]:attrs[]\ncomment:# foo\nrecipe:baz:false:params[]:deps[]:subseq[]:lines[]:attrs[]",
  )
}

///|
test "upstream parser::tests::doc_comment_recipe_clear" {
  let ast = try! parse(parser_remaining_source("# foo\nbar:\nbaz:\n"))
  assert_eq(
    ast.semantic_key(),
    "comment:# foo\nrecipe:bar:false:params[]:deps[]:subseq[]:lines[]:attrs[]\nrecipe:baz:false:params[]:deps[]:subseq[]:lines[]:attrs[]",
  )
}

///|
test "upstream parser::tests::parse_complex" {
  let ast = try! parse(
    parser_remaining_source(
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
fn assert_justfile_parser_items(text : String, expected : Int) -> Unit raise {
  let ast = try! parse(parser_remaining_source(text))
  assert_eq(ast.items().length(), expected)
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
test "upstream justfile::tests::parse_alias_before_target" {
  let ast = try! parse(
    parser_remaining_source("alias f := foo\nfoo:\n echo a\n"),
  )
  guard ast.items()[0] is Alias(alias_item) else { fail("expected alias") }
  assert_eq(alias_item.target(), "foo")
}

///|
test "upstream justfile::tests::parse_alias_after_target" {
  let ast = try! parse(
    parser_remaining_source("foo:\n echo a\nalias f := foo\n"),
  )
  guard ast.items()[1] is Alias(alias_item) else { fail("expected alias") }
  assert_eq(alias_item.name(), "f")
}

///|
test "upstream justfile::tests::parse_alias_with_comment" {
  let ast = try! parse(
    parser_remaining_source("alias f := foo # comment\nfoo:\n echo a\n"),
  )
  guard ast.items()[1] is TrailingComment(text~, ..) else {
    fail("expected comment")
  }
  assert_eq(text, "# comment")
}

///|
test "upstream justfile::tests::parse_assignments" {
  let ast = try! parse(
    parser_remaining_source("a := '0'\nc := a + b + a + b\nb := '1'\n"),
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
    parser_remaining_source(
      "a := `echo hello`\nc := a + b + a + b\nb := `echo goodbye`\n",
    ),
  )
  assert_eq(
    ast.items()[0].semantic_key(),
    "assignment:a:false:false:backtick:backtick(echo hello):attrs[]",
  )
}

///|
test "upstream justfile::tests::parse_interpolation_backticks" {
  let ast = try! parse(parser_remaining_source("a:\n echo {{`echo hi`}}\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  guard recipe.lines()[0].fragments()[1] is Interpolation(expression~, ..) else {
    fail("expected interpolation")
  }
  assert_eq(expression.semantic_key(), "backtick:backtick(echo hi)")
}

///|
test "upstream justfile::tests::parse_string_default" {
  let ast = try! parse(parser_remaining_source("foo x='abc':\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "string:raw(abc)",
  )
}

///|
test "upstream justfile::tests::parse_raw_string_default" {
  let ast = try! parse(parser_remaining_source("foo x='abc':\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.parameters()[0].default_value().unwrap().kind(), "string")
}

///|
test "upstream justfile::tests::parse_variadic" {
  let ast = try! parse(parser_remaining_source("foo +bar:\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_true(recipe.parameters()[0].variadic())
}

///|
test "upstream justfile::tests::parse_variadic_string_default" {
  let ast = try! parse(parser_remaining_source("foo +bar='baz':\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "string:raw(baz)",
  )
  assert_eq(recipe.parameters()[0].variadic_minimum(), 1)
}

///|
test "upstream justfile::tests::parameter_default_backtick" {
  let ast = try! parse(parser_remaining_source("f x=`echo hello`:\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "backtick:backtick(echo hello)",
  )
}

///|
test "upstream justfile::tests::parameter_default_concatenation_string" {
  let ast = try! parse(parser_remaining_source("f x=(`echo hello` + 'foo'):\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_true(
    recipe.parameters()[0].default_value().unwrap().kind() == "parenthesized",
  )
}

///|
test "upstream justfile::tests::parameter_default_concatenation_variable" {
  let ast = try! parse(parser_remaining_source("f x=(a + b):\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "parenthesized:(binary:concat(var:a,var:b))",
  )
}

///|
test "upstream justfile::tests::parameter_default_multiple" {
  let ast = try! parse(parser_remaining_source("f a='x' b='y':\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.parameters().length(), 2)
}

///|
test "upstream justfile::tests::parameters" {
  let ast = try! parse(parser_remaining_source("a b c:\n {{b}} {{c}}\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.parameters().map(fn(parameter) { parameter.name() }), [
    "b", "c",
  ])
}

///|
test "upstream justfile::tests::string_in_group" {
  let ast = try! parse(parser_remaining_source("x := ('0'   )\n"))
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:parenthesized:(string:raw(0)):attrs[]",
  )
}

///|
test "upstream justfile::tests::concatenation_in_group" {
  let ast = try! parse(parser_remaining_source("x := ('0' + '1')\n"))
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:parenthesized:(binary:concat(string:raw(0),string:raw(1))):attrs[]",
  )
}

///|
test "upstream justfile::tests::unary_functions" {
  let ast = try! parse(
    parser_remaining_source("x := arch()\n\na:\n {{os()}} {{os_family()}}\n"),
  )
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  assert_eq(assignment.value().kind(), "call")
}

///|
test "upstream justfile::tests::env_functions" {
  let ast = try! parse(
    parser_remaining_source(
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
}

///|
test "upstream justfile::tests::eof_test" {
  let ast = try! parse(parser_remaining_source("x:\ny:\nz:\na b c: x y z"))
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
    parser_remaining_source(
      "practicum := 'hello'\ninstall:\n\t#!/bin/sh\n\tif [[ -f {{practicum}} ]]; then\n\t\treturn\n\tfi\n",
    ),
  )
  guard ast.items()[1] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.lines().length(), 4)
}

///|
test "upstream justfile::tests::parse_simple_shebang" {
  let ast = try! parse(parser_remaining_source("a:\n #!\n  print(1)\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.lines().length(), 2)
}

///|
test "upstream justfile::tests::parameter_default_string" {
  let ast = try! parse(parser_remaining_source("foo x='abc':\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(
    recipe.parameters()[0].default_value().unwrap().semantic_key(),
    "string:raw(abc)",
  )
}

///|
test "upstream justfile::tests::parameter_default_raw_string" {
  let ast = try! parse(parser_remaining_source("foo x='abc':\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.parameters()[0].default_value().unwrap().kind(), "string")
}

///|
test "upstream justfile::tests::parse_complex" {
  let ast = try! parse(
    parser_remaining_source(
      "x:\ny:\nz:\nfoo := \"xx\"\nbar := foo\ngoodbye := \"y\"\nhello a b    c   : x y    z #hello\n  #! blah\n  #blarg\n  {{ foo + bar}}abc{{ goodbye\t  + \"x\" }}xyz\n  1\n  2\n  3\n",
    ),
  )
  assert_eq(ast.items().length(), 7)
  guard ast.items()[6] is Recipe(recipe) else { fail("expected recipe") }
  assert_eq(recipe.parameters().length(), 3)
  assert_eq(recipe.dependencies().length(), 3)
  assert_eq(recipe.lines().length(), 6)
}
