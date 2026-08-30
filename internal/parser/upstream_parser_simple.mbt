///|
test "upstream parser::tests::addition_chained" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "x := a + b + c\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:binary:concat(var:a,binary:concat(var:b,var:c)):attrs[]",
  )
}

///|
test "upstream parser::tests::addition_single" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "x := a + b\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:binary:concat(var:a,var:b):attrs[]",
  )
}

///|
test "upstream parser::tests::alias_equals" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "alias t := test\n",
    ),
  )
  assert_eq(ast.semantic_key(), "alias:t=test:attrs[]")
}

///|
test "upstream parser::tests::call_multiple_args" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "x := env_var_or_default(y, z)\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:call:env_var_or_default[var:y,var:z]:attrs[]",
  )
}

///|
test "upstream parser::tests::call_one_arg" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "x := env_var(y)\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:call:env_var[var:y]:attrs[]",
  )
}

///|
test "upstream parser::tests::call_trailing_comma" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "x := env_var(y,)\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:call:env_var[var:y]:attrs[]",
  )
}

///|
test "upstream parser::tests::comparison" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "a := b == c\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:binary:equal(var:b,var:c):attrs[]",
  )
}

///|
test "upstream parser::tests::comparison_binds_looser_than_concatenation" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "a := b + c == d + e\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:binary:equal(binary:concat(var:b,var:c),binary:concat(var:d,var:e)):attrs[]",
  )
}

///|
test "upstream parser::tests::comparison_binds_tighter_than_logical_operators" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "a := b == c && d == e || f == g\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:binary:or(binary:and(binary:equal(var:b,var:c),binary:equal(var:d,var:e)),binary:equal(var:f,var:g)):attrs[]",
  )
}

///|
test "upstream parser::tests::recipe" {
  let ast = try! parse(
    @source.Source::from_text(@source.SourceId::new(890), "justfile", "foo:"),
  )
  assert_eq(
    ast.semantic_key(),
    "recipe:foo:false:params[]:deps[]:subseq[]:lines[]:attrs[]",
  )
}

///|
test "upstream parser::tests::recipe_dependency_single" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "foo: bar",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "recipe:foo:false:params[]:deps[bar:false:[]]:subseq[]:lines[]:attrs[]",
  )
}

///|
test "upstream parser::tests::conditional" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "a := if b { c } else { d }\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:if(var:b,var:c,var:d):attrs[]",
  )
}

///|
test "upstream parser::tests::conditional_concatenations" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "a := if b0 + b1 { c0 + c1 } else { d0 + d1 }\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:if(binary:concat(var:b0,var:b1),binary:concat(var:c0,var:c1),binary:concat(var:d0,var:d1)):attrs[]",
  )
}

///|
test "upstream parser::tests::conditional_inverted" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "a := if b != c { d } else { e }\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:if(binary:not-equal(var:b,var:c),var:d,var:e):attrs[]",
  )
}

///|
test "upstream parser::tests::conditional_nested_lhs" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "a := if if b == c { d } else { e } == c { d } else { e }\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:if(binary:equal(if(binary:equal(var:b,var:c),var:d,var:e),var:c),var:d,var:e):attrs[]",
  )
}

///|
test "upstream parser::tests::conditional_nested_otherwise" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "a := if b { c } else { if d { e } else { f } }\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:if(var:b,var:c,if(var:d,var:e,var:f)):attrs[]",
  )
}

///|
test "upstream parser::tests::conditional_nested_rhs" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "a := if c == if b == c { d } else { e } { d } else { e }\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:if(binary:equal(var:c,if(binary:equal(var:b,var:c),var:d,var:e)),var:d,var:e):attrs[]",
  )
}

///|
test "upstream parser::tests::conditional_nested_then" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "a := if b { if c { d } else { e } } else { f }\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:if(var:b,if(var:c,var:d,var:e),var:f):attrs[]",
  )
}

///|
test "upstream parser::tests::double_negation" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "a := !!b\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:unary:not(unary:not(var:b)):attrs[]",
  )
}

///|
test "upstream parser::tests::negation" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "a := !b\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:unary:not(var:b):attrs[]",
  )
}

///|
test "upstream parser::tests::negation_binds_tighter_than_comparison" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "a := !b == c\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:binary:equal(unary:not(var:b),var:c):attrs[]",
  )
}

///|
test "upstream parser::tests::string_escape_carriage_return" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "x := \"foo\\rbar\"\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:string:cooked(foo\rbar):attrs[]",
  )
}

///|
test "upstream parser::tests::string_escape_newline" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "x := \"foo\\nbar\"\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:string:cooked(foo\nbar):attrs[]",
  )
}

///|
test "upstream parser::tests::string_escape_quote" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "x := \"foo\\\"bar\"\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:string:cooked(foo\"bar):attrs[]",
  )
}

///|
test "upstream parser::tests::string_escape_slash" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "x := \"foo\\\\bar\"\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:string:cooked(foo\\bar):attrs[]",
  )
}

///|
test "upstream parser::tests::string_escape_suppress_newline" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "x := \"foo\\\nbar\"\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:string:cooked(foobar):attrs[]",
  )
}

///|
test "upstream parser::tests::string_escape_tab" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "x := \"foo\\tbar\"\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:x:false:false:string:cooked(foo\tbar):attrs[]",
  )
}

///|
test "upstream parser::tests::string_escapes" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "a := \"\\n\\t\\r\\\"\\\\\"\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:string:cooked(\n\t\r\"\\):attrs[]",
  )
}

///|
test "upstream parser::tests::string_quote_escape" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "a := \"hello\\\"\"\n",
    ),
  )
  assert_eq(
    ast.semantic_key(),
    "assignment:a:false:false:string:cooked(hello\"):attrs[]",
  )
}

///|
test "upstream parser::tests::variable" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(890),
      "justfile",
      "x := y\n",
    ),
  )
  assert_eq(ast.semantic_key(), "assignment:x:false:false:var:y:attrs[]")
}
