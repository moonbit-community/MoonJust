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
test "upstream parser::tests::list_concatenation_single" {
  let ast = try! parse(parser_upstream_source("x := a ++ b\n"))
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:binary:list-concat(var:a,var:b):attrs[]",
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
test "upstream justfile::tests::concatenation_in_group" {
  let ast = try! parse(parser_upstream_source("x := ('0' + '1')\n"))
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:parenthesized:(binary:concat(string:raw(0),string:raw(1))):attrs[]",
  )
}

///|
test "upstream justfile::tests::unary_functions" {
  let ast = try! parse(
    parser_upstream_source("x := arch()\n\na:\n {{os()}} {{os_family()}}\n"),
  )
  guard ast.items()[0] is Assignment(assignment) else {
    fail("expected assignment")
  }
  assert_eq(assignment.value().kind(), "call")
}

///|
test "upstream justfile::tests::env_functions" {
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
}
