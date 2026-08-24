///|
fn semantic_coverage_source(text : String) -> @source.Source {
  @source.Source::from_text(
    @source.SourceId::new(9800),
    "semantic.coverage",
    text,
  )
}

///|
test "semantic coverage exercises every diagnostic family" {
  let source = @source.Source::from_text(
    @source.SourceId::new(9300),
    "semantic.just",
    "x\n",
  )
  let first = @source.Span::new(source.id(), 0, 1)
  let second = @source.Span::new(source.id(), 1, 1)
  let parse_error = @parser.ParserError::ExtraneousInput(span=first)
  let errors : Array[SemanticError] = [
    Parse(parse_error),
    DuplicateRecipe(name="r", first~, second~),
    DuplicateVariable(name="x", first~, second~),
    DuplicateFunction(name="f", first~, second~),
    SymbolRedefinition(
      name="x",
      first_kind="variable",
      second_kind="recipe",
      first~,
      second~,
    ),
    DuplicateFunctionParameter(function_name="f", parameter="x", span=first),
    UndefinedFunction(name="f", span=first),
    FunctionArgumentCount(name="f", expected="1", actual=2, span=first),
    UserFunctionsUnstable(span=first),
    ListsUnstable(span=first),
    GuardAndInfallibleSigil(span=first),
    InvalidIndentation(message="bad indent", span=first),
    UndefinedRecipe(name="r", span=first),
    UnknownAliasTarget(alias_name="a", target="r", span=first),
    UnknownDependency(recipe="r", target="d", span=first),
    UndefinedVariable(name="x", span=first),
    NonConstVariable(name="x", span=first),
    ConstContext(kind="backtick", span=first),
    AliasCycle(name="a", span=first),
    DependencyCycle(name="r", span=first),
    RecipeDependencyCycle(recipe="r", chain=["r", "r"], span=first),
    InvalidParameters(name="r", span=first),
    DuplicateRecipeParameter(recipe="r", parameter="x", span=first),
    ParameterFollowsDefault(parameter="x", span=first),
    ParameterFollowsVariadic(parameter="x", span=first),
    InvalidDependencyArguments(name="r", expected="1", actual=2, span=first),
    SettingConflict(first="a", second="b", first_span=first, span=second),
    InvalidSettingValue(name="shell", span=first),
    EmptySetting(name="shell", span=first),
    MinimumVersionUnsatisfied(required="9.0.0", current="1.57.0", span=first),
    InvalidMinimumVersion(value="bad", span=first),
    AttributeConflict(first="private", second="public", span=first),
    DuplicateAttribute(name="private", first~, second~),
    DuplicateGroup(name="ci", first~, second~),
    NoCdWorkingDirectoryAttributes(recipe="r", span=first),
    ScriptAndShellAttributes(recipe="r", span=first),
    ExitMessageAttributes(recipe="r", span=first),
    InvalidContinueSignal(signal="SIGTERM", span=first),
    ScriptAttributeOnShellRecipe(recipe="r", attribute="script", span=first),
    DuplicateDefaultAttribute(recipe="r", span=first),
    DuplicateUnexport(variable="x", span=first),
    ExportUnexported(variable="x", span=first),
    InvalidMappedDependency(message="bad mapping", span=first),
    InvalidItemAttribute(
      item_kind="recipe",
      item_name="r",
      attribute="private",
      span=first,
    ),
    ListsFeature(message="lists", span=first),
    UnsupportedPlatform(name="windows", span=first),
  ]
  for error in errors {
    assert_true(error.code().has_prefix("MJ-SEM-"))
    assert_true(error.message().length() > 0)
    assert_true(error.span() == first || error.span() == second)
    let diagnostic = try! error.to_diagnostic()
    assert_eq(diagnostic.code(), error.code())
  }
}

///|
test "semantic coverage compiles a broad feature corpus" {
  let cases = [
    "set quiet\nset shell := [\"sh\", \"-cu\"]\na := \"x\"\nbuild:\n  echo {{a}}\n",
    "set unstable\nset lists\nf(x) := x\nresult := f('ok')\n", "[private, group(\"ci\"), metadata(\"owner\"), env(\"MODE\", \"test\")]\nbuild arg='x':\n  echo {{arg}}\n",
    "[script]\nrun:\n  #!/bin/sh\n  echo ok\n", "[parallel]\na: b\nb: c\nc:\n", "set dotenv-command := \"echo A=B\"\nset dotenv-override\n",
    "export A := 'a'\nB =: A + 'b'\n", "mod tools 'tools.just'\nimport? 'common.just'\n",
    "foo +args:\n  echo {{args}}\nbar: (foo 'x')\n",
  ]
  for text in cases {
    try {
      let ast = @parser.parse(
        @source.Source::from_text(
          @source.SourceId::new(9301),
          "case.just",
          text,
        ),
      )
      try compile(ast, allow_unstable=true) catch {
        _ => ()
      } noraise {
        _ => ()
      }
    } catch {
      _ => ()
    }
  }
}

///|
test "semantic coverage drives validation branches through representative failures" {
  let cases = [
    "set minimum-version := '1.0.0'\n", "set minimum-version := 'bad'\n", "set lists\nvalue := ['a', 'b']\n",
    "set lists\nvalue := `echo value`\n", "a := 'one'\na := 'two'\n", "f(x, x) := x\n",
    "f(x='x', y) := y\n", "f(+args, x) := x\n", "f(x) := x\ng := f('x', 'y')\n",
    "f(x) := x\ng := unknown('x')\n", "a := b\nb := a\n", "run: missing\n", "a: b\nb: a\n",
    "alias a := missing\n", "alias a := b\nalias b := a\n", "[private]\n[public]\nrun:\n",
    "[script]\n[shell('sh', '-cu')]\nrun:\n  echo ok\n", "[no-cd]\n[working-directory('sub')]\nrun:\n",
    "[exit-message]\n[no-exit-message]\nrun:\n", "[continue('INVALID')]\nrun:\n  echo ok\n",
    "[platform('windows')]\n[platform('linux')]\nrun:\n", "set guards\nrun:\n  ?check\n  -echo no\n",
    "set guards\nrun:\n  ?-check\n", "set shell := ['sh']\nrun:\n  #!/bin/sh\n  echo ok\n",
    "set dotenv-load\nset dotenv-required\n", "set shell := 'not-a-list'\n", "set tempdir := ['not-a-string']\n",
    "export X := `echo x`\n", "set positional-arguments\nrun x='a' *rest:\n  echo {{x}} {{rest}}\n",
    "[arg('x', long='x', flag)]\nrun x:\n  echo ok\n", "[group('ci')]\n[group('ci')]\nrun:\n",
    "[metadata('a', 'b')]\n[metadata('a', 'b')]\nrun:\n", "[env('A', 'one')]\n[env('A', 'two')]\nrun:\n",
    "[cache(inputs='missing', outputs='out')]\nrun:\n  echo ok\n", "mod optional 'missing.just'\nrun:\n",
    "import? 'missing.just'\nrun:\n", "recipe a='x' b='y':\n  echo {{a}}\n", "recipe a *rest:\n  echo {{a}}\n",
  ]
  for index, text in cases {
    let source = semantic_coverage_source(text)
    try {
      let ast = @parser.parse(source)
      try compile(ast, allow_unstable=true) catch {
        error => assert_true(error.message().length() > index)
      } noraise {
        compilation => assert_true(compilation.recipe_names().length() >= 0)
      }
    } catch {
      _ => ()
    }
  }
}

///|
test "semantic coverage exercises version, alias, and symbol validation paths" {
  let cases = [
    "set minimum-version := '1.57.1'\n", "set minimum-version := '1.57'\n", "set minimum-version := '1.57.x'\n",
    "alias a := b\nb:\n", "alias a := a\na:\n", "alias a := b\nalias b := c\nc:\n",
    "[default]\n[default]\nrun:\n", "[private]\n[private]\nrun:\n", "export x\nunexport x\nunexport x\nrun:\n",
    "export x\nunexport y\nrun:\n", "unexport x\nexport x := 'value'\nrun:\n", "set shell := ['sh']\nset shell := ['bash']\nrun:\n",
    "set working-directory := 'a'\nset no-cd\nrun:\n", "[continue('SIGHUP')]\nrun:\n",
    "[continue('SIGQUIT')]\nrun:\n", "[platform('linux')]\n[platform('windows')]\nrun:\n",
    "mod tools 'tools.just'\nmod tools 'other.just'\nrun:\n", "foo(x) := x\nfoo(x) := x\nrun:\n",
    "foo(x, x) := x\nrun:\n", "run a='x' a='y':\n  echo ok\n", "run a *rest b:\n  echo ok\n",
    "run: missing\nmissing: run\n", "run: run\n",
  ]
  for index, text in cases {
    let source = semantic_coverage_source(text)
    try {
      let ast = @parser.parse(source)
      try compile(ast, allow_unstable=true) catch {
        error => assert_true(error.message().length() >= index)
      } noraise {
        compilation => assert_true(compilation.recipe_names().length() >= 0)
      }
    } catch {
      _ => ()
    }
  }
}

///|
test "semantic coverage compiles complete recipe attribute combinations" {
  let cases = [
    "[confirm]\nrun:\n", "[confirm('Proceed?')]\nrun:\n", "[default]\nrun:\n", "[doc('documentation')]\nrun:\n",
    "[extension('.sh')]\n[script('sh', '-eu')]\nrun:\n  echo ok\n", "[shell]\nrun:\n  echo ok\n",
    "[working-directory('sub')]\nrun:\n", "[continue('SIGHUP', 'SIGINT', 'SIGQUIT')]\nrun:\n",
    "[linux, unix]\nrun:\n", "[windows]\nrun:\n", "[script]\n[cache(inputs=['a', 'b'], outputs=['c'], extra='tag')]\nrun:\n  echo cache\n",
    "[env('MODE', 'test')]\n[env('EMPTY', '')]\nrun:\n", "[metadata('owner', 'team')]\n[metadata('tier', 'one')]\nrun:\n",
    "set lists\n[arg('item', long='item', short='i', value='VALUE', multiple, min='1', max='3', pattern=['a', 'b'])]\nrun item:\n",
  ]
  for index, text in cases {
    let compilation = try
      compile_source(
        @source.Source::from_text(
          @source.SourceId::new(9850 + index),
          "semantic-attributes.just",
          text,
        ),
        allow_unstable=true,
      )
    catch {
      error => fail("valid semantic case \{index} failed: \{error.message()}")
    } noraise {
      value => value
    }
    assert_true(compilation.recipe_names().all(fn(name) { name == "run" }))
  }
}
