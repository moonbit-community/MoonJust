///|
fn source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(1), "justfile", text)
}

///|
test "compilation exposes ordered symbols and typed settings" {
  let ast = try! @parser.parse(
    source(
      "set quiet\nexport NAME := `value`\n[group(\"build\")]\nbuild:\n  echo {{NAME}}\n",
    ),
  )
  let compiled = try! compile(ast)
  assert_true(compiled.settings().bool("quiet"))
  assert_eq(compiled.variable_names(), ["NAME"])
  assert_eq(compiled.recipe_names(), ["build"])
  assert_eq(compiled.recipe_attributes("build").unwrap().group(), Some("build"))
}

///|
test "duplicate and cyclic definitions are static errors" {
  let duplicate = @parser.parse(source("x := \"one\"\nx := \"two\"\n")) catch {
    error => {
      println(error.message())
      fail("duplicate fixture did not parse")
      @syntax.Ast::new(@source.SourceId::new(1), [], source("").full_span())
    }
  }
  try compile(duplicate) catch {
    DuplicateVariable(name~, ..) => assert_eq(name, "x")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected duplicate variable")
  }
  let cycle = try! @parser.parse(source("a: b\nb: a\n"))
  try compile(cycle) catch {
    DependencyCycle(name~, ..) => assert_true(name == "a" || name == "b")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected dependency cycle")
  }
}

///|
test "settings and attributes expose complete typed contracts" {
  assert_eq(setting_specs().length(), 29)
  let ast = try! @parser.parse(
    source(
      "set quiet\nset minimum-version := \"1.57.0\"\n" +
      "[confirm, default, env(\"MODE\", \"test\"), metadata(\"ci\")]\n" +
      "build:\n",
    ),
  )
  let compiled = try! compile(ast)
  assert_true(compiled.settings().bool("quiet"))
  assert_eq(
    compiled.settings().get("minimum-version").unwrap().as_text(),
    Some("1.57.0"),
  )
  let attributes = compiled.recipe_attributes("build").unwrap()
  assert_true(attributes.confirm())
  assert_true(attributes.default() is None)
  assert_eq(attributes.env().length(), 1)
  assert_eq(attributes.metadata(), ["ci"])
}
