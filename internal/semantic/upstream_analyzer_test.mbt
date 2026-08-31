///|
fn analyzer_source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(910), "justfile", text)
}

///|
test "upstream analyzer::tests::duplicate_recipe" {
  try @semantic.compile_source(analyzer_source("a:\nb:\na:")) catch {
    DuplicateRecipe(name~, first~, second~) => {
      assert_eq(name, "a")
      assert_eq(first.start_byte(), 0)
      assert_eq(second.start_byte(), 6)
      assert_eq(second.length(), 1)
    }
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected duplicate recipe error")
  }
}

///|
test "upstream analyzer::tests::duplicate_variable" {
  try
    @semantic.compile_source(analyzer_source("a := \"0\"\na := \"0\""))
  catch {
    DuplicateVariable(name~, first~, second~) => {
      assert_eq(name, "a")
      assert_eq(first.start_byte(), 0)
      assert_eq(second.start_byte(), 9)
      assert_eq(second.length(), 1)
    }
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected duplicate variable error")
  }
}

///|
test "upstream analyzer::tests::duplicate_variadic_parameter" {
  try @semantic.compile_source(analyzer_source("a b +b:")) catch {
    DuplicateRecipeParameter(recipe~, parameter~, span~) => {
      assert_eq(recipe, "a")
      assert_eq(parameter, "b")
      assert_eq(span.start_byte(), 5)
      assert_eq(span.length(), 1)
    }
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected duplicate parameter error")
  }
}

///|
test "upstream analyzer::tests::required_after_default" {
  try @semantic.compile_source(analyzer_source("hello arg='foo' bar:")) catch {
    ParameterFollowsDefault(parameter~, span~) => {
      assert_eq(parameter, "bar")
      assert_eq(span.start_byte(), 16)
      assert_eq(span.length(), 3)
    }
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected parameter ordering error")
  }
}

///|
test "upstream analyzer::tests::undefined_function" {
  try @semantic.compile_source(analyzer_source("a := foo()")) catch {
    UndefinedFunction(name~, span~) => {
      assert_eq(name, "foo")
      assert_eq(span.start_byte(), 5)
      assert_eq(span.length(), 3)
    }
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected undefined function error")
  }
}

///|
test "upstream analyzer::tests::undefined_function_in_default" {
  try @semantic.compile_source(analyzer_source("a f=baz():")) catch {
    UndefinedFunction(name~, span~) => {
      assert_eq(name, "baz")
      assert_eq(span.start_byte(), 4)
      assert_eq(span.length(), 3)
    }
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected undefined function error")
  }
}

///|
test "upstream analyzer::tests::undefined_function_in_interpolation" {
  try @semantic.compile_source(analyzer_source("a:\n echo {{bar()}}")) catch {
    UndefinedFunction(name~, span~) => {
      assert_eq(name, "bar")
      assert_eq(span.start_byte(), 11)
      assert_eq(span.length(), 3)
    }
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected undefined function error")
  }
}

///|
fn assert_function_arity(
  text : String,
  function_name : String,
  expected_arity : String,
  actual_count : Int,
  start : Int,
  length : Int,
) -> Unit raise {
  try @semantic.compile_source(analyzer_source(text)) catch {
    FunctionArgumentCount(name~, expected~, actual~, span~) => {
      assert_eq(name, function_name)
      assert_eq(expected, expected_arity)
      assert_eq(actual, actual_count)
      assert_eq(span.start_byte(), start)
      assert_eq(span.length(), length)
    }
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected function argument count error")
  }
}

///|
test "upstream analyzer::tests::function_argument_count_nullary" {
  assert_function_arity("x := arch('foo')", "arch", "0", 1, 5, 4)
}

///|
test "upstream analyzer::tests::function_argument_count_unary" {
  assert_function_arity("x := env_var()", "env_var", "1", 0, 5, 7)
}

///|
test "upstream analyzer::tests::function_argument_count_binary" {
  assert_function_arity(
    "x := env_var_or_default('foo')", "env_var_or_default", "2", 1, 5, 18,
  )
}

///|
test "upstream analyzer::tests::function_argument_count_binary_plus" {
  assert_function_arity("x := join('foo')", "join", "2 or more", 1, 5, 4)
}

///|
test "upstream analyzer::tests::function_argument_count_ternary" {
  assert_function_arity("x := replace('foo')", "replace", "3", 1, 5, 7)
}

///|
test "upstream analyzer::tests::duplicate_parameter" {
  try @semantic.compile_source(analyzer_source("a b b:")) catch {
    DuplicateRecipeParameter(recipe~, parameter~, span~) => {
      assert_eq(recipe, "a")
      assert_eq(parameter, "b")
      assert_eq(span.start_byte(), 4)
      assert_eq(span.length(), 1)
    }
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected duplicate parameter error")
  }
}

///|
test "upstream analyzer::tests::function_argument_count_too_high_unary_opt" {
  assert_function_arity(
    "x := env('foo', 'foo', 'foo')", "env", "1 to 2", 3, 5, 3,
  )
}

///|
test "upstream analyzer::tests::function_argument_count_too_low_unary_opt" {
  assert_function_arity("x := env()", "env", "1 to 2", 0, 5, 3)
}

///|
test "upstream analyzer::tests::duplicate_alias" {
  try
    @semantic.compile_source(
      analyzer_source("alias foo := bar\nalias foo := baz"),
    )
  catch {
    SymbolRedefinition(name~, first_kind~, second_kind~, first~, second~) => {
      assert_eq(name, "foo")
      assert_eq(first_kind, "alias")
      assert_eq(second_kind, "alias")
      assert_eq(first.start_byte(), 0)
      assert_eq(second.start_byte(), 23)
      assert_eq(second.length(), 3)
    }
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected duplicate alias error")
  }
}

///|
test "upstream analyzer::tests::alias_shadows_recipe_after" {
  try
    @semantic.compile_source(
      analyzer_source("foo:\n  echo foo\nalias foo := bar\nbar:\n  echo bar"),
    )
  catch {
    SymbolRedefinition(name~, first_kind~, second_kind~, first~, second~) => {
      assert_eq(name, "foo")
      assert_eq(first_kind, "recipe")
      assert_eq(second_kind, "alias")
      assert_eq(first.start_byte(), 0)
      assert_eq(second.start_byte(), 22)
      assert_eq(second.length(), 3)
    }
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected alias redefinition error")
  }
}

///|
test "upstream analyzer::tests::alias_shadows_recipe_before" {
  try
    @semantic.compile_source(
      analyzer_source("bar: \n  echo bar\nalias foo := bar\nfoo:\n  echo foo"),
    )
  catch {
    SymbolRedefinition(name~, first_kind~, second_kind~, first~, second~) => {
      assert_eq(name, "foo")
      assert_eq(first_kind, "alias")
      assert_eq(second_kind, "recipe")
      assert_eq(first.start_byte(), 17)
      assert_eq(second.start_byte(), 34)
      assert_eq(second.length(), 3)
    }
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected recipe redefinition error")
  }
}

///|
test "upstream analyzer::tests::unknown_alias_target" {
  try @semantic.compile_source(analyzer_source("alias foo := bar\n")) catch {
    UnknownAliasTarget(alias_name~, target~, span~) => {
      assert_eq(alias_name, "foo")
      assert_eq(target, "bar")
      assert_eq(span.start_byte(), 6)
      assert_eq(span.length(), 3)
    }
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unknown alias target error")
  }
}

///|
test "upstream parser::tests::concatenation_in_default" {
  try @semantic.compile_source(analyzer_source("foo a=c+d e:")) catch {
    Parse(UnexpectedConstruct(expected~, found~, span~)) => {
      assert_eq(expected, "no parameters after variadic parameter")
      assert_eq(found, "e")
      assert_eq(span.start_byte(), 10)
      assert_eq(span.length(), 1)
    }
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected parameter ordering error")
  }
}

///|
test "upstream analyzer::tests::extra_whitespace" {
  try @semantic.compile_source(analyzer_source("a:\n blah\n  blarg")) catch {
    InvalidIndentation(message~, span~) => {
      assert_eq(message, "recipe line has extra leading whitespace")
      assert_eq(span.start_byte(), 10)
      assert_eq(span.length(), 6)
    }
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected extra whitespace error")
  }
}

///|
fn assert_undefined_variable(
  text : String,
  expected_name : String,
  start : Int,
) -> Unit raise {
  try @semantic.compile_source(analyzer_source(text)) catch {
    UndefinedVariable(name~, span~) => {
      assert_eq(name, expected_name)
      assert_eq(span.start_byte(), start)
      assert_eq(span.length(), expected_name.length())
    }
    _ => fail("unexpected semantic error")
  } noraise {
    _ => fail("expected undefined variable error")
  }
}

///|
test "upstream variable_resolver::tests::unknown_expression_variable" {
  assert_undefined_variable("x := yy", "yy", 5)
}

///|
test "upstream variable_resolver::tests::undefined_function_parameter" {
  assert_undefined_variable("x := env_var(yy)", "yy", 13)
}

///|
test "upstream variable_resolver::tests::undefined_function_parameter_binary_first" {
  assert_undefined_variable("x := env_var_or_default(yy, 'foo')", "yy", 24)
}

///|
test "upstream variable_resolver::tests::undefined_function_parameter_binary_second" {
  assert_undefined_variable("x := env_var_or_default('foo', yy)", "yy", 31)
}

///|
test "upstream variable_resolver::tests::function_parameters_shadow_variables" {
  let compilation = try! @semantic.compile_source(
    analyzer_source("set unstable\na := f('x')\nf(a) := a"),
  )
  assert_eq(compilation.function_names().length(), 1)
}

///|
fn assert_recipe_cycle(
  text : String,
  expected_recipe : String,
  start : Int,
) -> Unit raise {
  try @semantic.compile_source(analyzer_source(text)) catch {
    DependencyCycle(name~, span~) => {
      assert_eq(name, expected_recipe)
      assert_eq(span.start_byte(), start)
    }
    _ => fail("unexpected semantic error")
  } noraise {
    _ => fail("expected recipe dependency cycle")
  }
}

///|
test "upstream recipe_resolver::tests::circular_recipe_dependency" {
  assert_recipe_cycle("a: b\nb: a", "b", 8)
}

///|
test "upstream recipe_resolver::tests::self_recipe_dependency" {
  assert_recipe_cycle("a: a", "a", 3)
}

///|
test "upstream recipe_resolver::tests::unknown_dependency" {
  try @semantic.compile_source(analyzer_source("a: b")) catch {
    UnknownDependency(recipe~, target~, span~) => {
      assert_eq(recipe, "a")
      assert_eq(target, "b")
      assert_eq(span.start_byte(), 3)
    }
    _ => fail("unexpected semantic error")
  } noraise {
    _ => fail("expected unknown dependency")
  }
}

///|
test "upstream recipe_resolver::tests::unknown_interpolation_variable" {
  assert_undefined_variable("x:\n {{   hello}}", "hello", 9)
}

///|
test "upstream recipe_resolver::tests::unknown_second_interpolation_variable" {
  assert_undefined_variable(
    "wtf:=\"x\"\nx:\n echo\n foo {{wtf}} {{ lol }}", "lol", 34,
  )
}

///|
test "upstream recipe_resolver::tests::unknown_variable_in_default" {
  assert_undefined_variable("a f=foo:", "foo", 4)
}

///|
test "upstream recipe_resolver::tests::unknown_variable_in_dependency_argument" {
  assert_undefined_variable("bar x:\nfoo: (bar baz)", "baz", 17)
}
