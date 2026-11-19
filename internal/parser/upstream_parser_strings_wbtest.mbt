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
test "upstream parser::tests::indented_string_cooked" {
  let ast = try! parse(
    parser_upstream_source("x := \"\"\"\n  \\tfoo\\t\n  \\tbar\\n\n\"\"\"\n"),
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
    parser_upstream_source("x := \"\"\"\n\\tfoo\\t\n  \\tbar\\n\n\"\"\"\n"),
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
    parser_upstream_source("x := ```\n  \\tfoo\\t\n  \\tbar\\n\n```\n"),
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
    parser_upstream_source("x := ```\n\\tfoo\\t\n  \\tbar\\n\n```\n"),
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
    parser_upstream_source(
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
test "upstream string::indented_backtick_string_escapes" {
  let ast = try! parse(
    parser_upstream_source(
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
    parser_upstream_source("a := '''\n  foo\\n\n  bar\n'''\n"),
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
    parser_upstream_source("x := '''\r\nfoo\r\n\r\nbar\r\n'''\r\n"),
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
    parser_upstream_source(
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
test "upstream justfile::tests::parse_interpolation_backticks" {
  let ast = try! parse(parser_upstream_source("a:\n echo {{`echo hi`}}\n"))
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  guard recipe.lines()[0].fragments()[1] is Interpolation(expression~, ..) else {
    fail("expected interpolation")
  }
  assert_eq(expression.semantic_key(), "backtick:backtick(echo hi)")
}

///|
test "upstream justfile::tests::string_in_group" {
  let ast = try! parse(parser_upstream_source("x := ('0'   )\n"))
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:parenthesized:(string:raw(0)):attrs[]",
  )
}
