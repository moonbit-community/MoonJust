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
  assert_eq(compiled.recipe_attributes("build").unwrap().groups(), ["build"])
}

///|
test "recipe groups allow distinct memberships and reject duplicates" {
  let ast = try! @parser.parse(
    source("[group(\"alpha\")]\n[group(\"beta\")]\nbuild:\n"),
  )
  let attributes = (try! compile(ast)).recipe_attributes("build").unwrap()
  assert_eq(attributes.groups(), ["alpha", "beta"])
  let duplicate = try! @parser.parse(
    source("[group(\"alpha\")]\n[group(\"alpha\")]\nbuild:\n"),
  )
  try compile(duplicate) catch {
    DuplicateGroup(name="alpha", ..) => ()
    error => fail("unexpected duplicate group error: \{Repr(error)}")
  } noraise {
    _ => fail("expected duplicate group error")
  }
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

///|
test "semantic validation checks minimum version, dependency arity, and recipe variables" {
  let too_new = @parser.parse(source("set minimum-version := \"9.0.0\"\n"))
  try compile(too_new) catch {
    MinimumVersionUnsatisfied(required~, ..) => assert_eq(required, "9.0.0")
    _ => fail("unexpected minimum-version error")
  } noraise {
    _ => fail("expected minimum-version error")
  }
  let arity = try! @parser.parse(source("build arg:\nrun: build\n"))
  try compile(arity) catch {
    InvalidDependencyArguments(name~, actual~, ..) => {
      assert_eq(name, "build")
      assert_eq(actual, 0)
    }
    _ => fail("unexpected dependency arity error")
  } noraise {
    _ => fail("expected dependency arity error")
  }
  let plus = try! @parser.parse(source("build +args:\nrun: build\n"))
  try compile(plus) catch {
    InvalidDependencyArguments(name="build", actual=0, ..) => ()
    _ => fail("unexpected plus-variadic arity error")
  } noraise {
    _ => fail("expected plus-variadic arity error")
  }
  let plus_many = try! @parser.parse(
    source("set lists\nbuild +args:\nrun: (build 'one' 'two')\n"),
  )
  try compile(plus_many, allow_unstable=true) catch {
    InvalidDependencyArguments(name="build", expected="at most 1", actual=2, ..) =>
      ()
    error => fail("unexpected variadic dependency arity error: \{Repr(error)}")
  } noraise {
    _ => fail("expected variadic dependency arity error")
  }
  let scalar_plus_many = try! @parser.parse(
    source("build +args:\nrun: (build 'one' 'two')\n"),
  )
  ignore(try! compile(scalar_plus_many))
  let star = try! @parser.parse(source("build *args:\nrun: build\n"))
  ignore(try! compile(star))
  let undefined = try! @parser.parse(source("build:\n  echo {{missing}}\n"))
  try compile(undefined) catch {
    UndefinedVariable(name~, ..) => assert_eq(name, "missing")
    _ => fail("unexpected recipe variable error")
  } noraise {
    _ => fail("expected recipe variable error")
  }
}

///|
test "option defaults do not constrain positional order and flags are optional dependencies" {
  let ordered = try! @parser.parse(
    source("[arg('bar', long)]\nfoo bar='baz' qux:\n"),
  )
  ignore(try! compile(ordered, allow_unstable=true))
  let flag_dependency = try! @parser.parse(
    source("set lists\n[arg('bar', long, flag)]\nfoo bar:\n\nbaz: foo\n"),
  )
  ignore(try! compile(flag_dependency, allow_unstable=true))
}

///|
test "false no-cd does not conflict with working-directory" {
  let ast = try! @parser.parse(
    source("set no-cd := false\nset working-directory := \"sub\"\n"),
  )
  let compiled = try! compile(ast)
  assert_false(compiled.settings().bool("no-cd"))
}

///|
test "dotenv command composes with override and false boolean settings" {
  let ast = try! @parser.parse(
    source(
      "set dotenv-command := \"echo KEY=value\"\n" +
      "set dotenv-load := false\n" +
      "set dotenv-required := false\n" +
      "set dotenv-override\n",
    ),
  )
  let settings = (try! compile(ast)).settings()
  assert_true(settings.has("dotenv-command"))
  assert_true(settings.bool("dotenv-override"))
}

///|
test "invalid module attributes point at the module name" {
  let source = @source.Source::from_text(
    @source.SourceId::new(901),
    "justfile",
    "[no-cd]\nmod foo\n",
  )
  let ast = try! @parser.parse(source)
  try compile(ast) catch {
    InvalidItemAttribute(span~, ..) => {
      assert_eq(span.start_byte(), 12)
      assert_eq(span.end_byte(), 15)
    }
    error => fail("unexpected module attribute error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid module attribute error")
  }
}

///|
test "dotenv command rejects enabled file loading settings" {
  for setting in ["dotenv-load", "dotenv-required"] {
    let ast = try! @parser.parse(
      source("set dotenv-command := \"echo KEY=value\"\nset \{setting}\n"),
    )
    try compile(ast) catch {
      SettingConflict(first="dotenv-command", second~, ..) =>
        assert_eq(second, setting)
      error => fail("unexpected dotenv conflict: \{Repr(error)}")
    } noraise {
      _ => fail("expected dotenv setting conflict")
    }
  }
}

///|
test "ignore-comments skips semantic analysis of ordinary recipe comments" {
  let ignored = try! @parser.parse(
    source("set ignore-comments\nfoo:\n  # {{ undefined }}\n"),
  )
  ignore(try! compile(ignored))
  let analyzed = try! @parser.parse(source("foo:\n  # {{ undefined }}\n"))
  try compile(analyzed) catch {
    UndefinedVariable(name~, ..) => assert_eq(name, "undefined")
    error => fail("unexpected comment analysis error: \{Repr(error)}")
  } noraise {
    _ => fail("expected undefined variable in non-ignored comment")
  }
}

///|
test "guard sigils are analyzed only at logical line boundaries" {
  let continuation = try! @parser.parse(
    source("set guards\nfoo:\n  echo a \\\n  -?bar\n"),
  )
  ignore(try! compile(continuation))
  let after_comment = try! @parser.parse(
    source("set guards\nset ignore-comments\nfoo:\n  # comment \\\n  -?bar\n"),
  )
  try compile(after_comment) catch {
    GuardAndInfallibleSigil(_) => ()
    error => fail("unexpected guard sigil error: \{Repr(error)}")
  } noraise {
    _ => fail("expected guard and infallible sigil conflict")
  }
}

///|
test "user functions validate instability definitions parameters calls and scope" {
  let unstable = try! @parser.parse(source("f() := 'value'\n"))
  try compile(unstable) catch {
    UserFunctionsUnstable(_) => ()
    error => fail("unexpected unstable function error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unstable function error")
  }
  let valid = try! compile(
    try! @parser.parse(
      source("outer := 'x'\nf(value,) := value + outer\nresult := f('y')\n"),
    ),
    allow_unstable=true,
  )
  assert_eq(valid.function_names(), ["f"])
  assert_eq(valid.function("f").unwrap().parameters().length(), 1)
  for
    text in [
      "f(a, a) := a\n", "f() := 'a'\nf() := 'b'\n", "f(x) := x\nresult := f('a', 'b')\n",
      "result := missing()\n",
    ] {
    try compile(try! @parser.parse(source(text)), allow_unstable=true) catch {
      DuplicateFunctionParameter(_)
      | DuplicateFunction(_)
      | FunctionArgumentCount(_)
      | UndefinedFunction(_) => ()
      error => fail("unexpected function validation error: \{Repr(error)}")
    } noraise {
      _ => fail("expected function validation error")
    }
  }
}

///|
test "recipe documentation preserves comments and doc suppression" {
  let compiled = try! compile(
    try! @parser.parse(
      source(
        "# First line\n# Second line\ndocumented:\n\n" +
        "# Hidden comment\n[doc]\nsuppressed:\n\n" +
        "# Replaced comment\n[doc('attribute') ]\nreplaced:\n",
      ),
    ),
  )
  assert_eq(compiled.recipe_doc("documented"), Some("First line Second line"))
  assert_eq(compiled.recipe_doc("suppressed"), None)
  assert_eq(compiled.recipe_doc("replaced"), Some("attribute"))
}

///|
test "continue signals and script-only extension are validated statically" {
  let invalid_signal = try! @parser.parse(
    source("[continue('SIGTERM')]\nfoo:\n"),
  )
  try compile(invalid_signal) catch {
    InvalidContinueSignal(signal="SIGTERM", ..) => ()
    error => fail("unexpected continue signal error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid continue signal error")
  }
  let shell_extension = try! @parser.parse(
    source("[extension('.txt')]\nfoo:\n"),
  )
  try compile(shell_extension) catch {
    ScriptAttributeOnShellRecipe(recipe="foo", attribute="extension", ..) => ()
    error => fail("unexpected extension error: \{Repr(error)}")
  } noraise {
    _ => fail("expected shell extension error")
  }
  ignore(
    try! compile(
      try! @parser.parse(source("[extension('.txt')]\nfoo:\n  #!/bin/sh\n")),
    ),
  )
}

///|
test "platform attributes select non-recipe definitions before duplicate checks" {
  let ast = try! @parser.parse(
    source(
      "[unix]\nx := 'unix'\n\n[windows]\nx := 'windows'\n\n" +
      "[unix]\nf() := 'unix'\n\n[windows]\nf() := 'windows'\n\n" +
      "foo:\n  @echo {{ x }} {{ f() }}\n",
    ),
  )
  let compiled = try! compile(
    ast,
    platform=TargetPlatform::new(Macos, true),
    allow_unstable=true,
  )
  assert_eq(compiled.variable_names(), ["x"])
  assert_eq(compiled.function_names(), ["f"])
  let copied_items : Array[@syntax.Item] = []
  for item in ast.items() {
    copied_items.push(item)
  }
  let copied = try! compile(
    @syntax.Ast::new(ast.source_id(), copied_items, ast.span()),
    platform=TargetPlatform::new(Macos, true),
    allow_unstable=true,
  )
  assert_eq(copied.variable_names(), ["x"])
  assert_eq(copied.function_names(), ["f"])
}
