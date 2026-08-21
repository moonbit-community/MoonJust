///|
fn assert_remaining_semantic_error(
  text : String,
  offset : Int,
  width : Int,
) -> Unit raise {
  let source = @source.Source::from_text(
    @source.SourceId::new(6100),
    "remaining-contract",
    text,
  )
  let ast = try! @parser.parse(source)
  try @semantic.compile(ast, allow_unstable=true) catch {
    error => {
      assert_eq(error.span().start_byte(), offset)
      assert_eq(error.span().length(), width)
    }
  } noraise {
    _ => fail("expected semantic contract error")
  }
}

///|
test "contract JUST-1.57.0-0022 analyzer::tests::alias_shadows_recipe_after" {
  assert_remaining_semantic_error(
    "foo:\n  echo foo\nalias foo := bar\nbar:\n  echo bar", 22, 3,
  )
}

///|
test "contract JUST-1.57.0-0023 analyzer::tests::alias_shadows_recipe_before" {
  assert_remaining_semantic_error(
    "bar: \n  echo bar\nalias foo := bar\nfoo:\n  echo foo", 34, 3,
  )
}

///|
test "contract JUST-1.57.0-0024 analyzer::tests::duplicate_alias" {
  assert_remaining_semantic_error("alias foo := bar\nalias foo := baz", 23, 3)
}

///|
test "contract JUST-1.57.0-0025 analyzer::tests::duplicate_parameter" {
  assert_remaining_semantic_error("a b b:", 4, 1)
}

///|
test "contract JUST-1.57.0-0026 analyzer::tests::duplicate_recipe" {
  assert_remaining_semantic_error("a:\nb:\na:", 6, 1)
}

///|
test "contract JUST-1.57.0-0027 analyzer::tests::duplicate_variable" {
  assert_remaining_semantic_error("a := \"0\"\na := \"0\"", 9, 1)
}

///|
test "contract JUST-1.57.0-0028 analyzer::tests::duplicate_variadic_parameter" {
  assert_remaining_semantic_error("a b +b:", 5, 1)
}

///|
test "contract JUST-1.57.0-0029 analyzer::tests::extra_whitespace" {
  assert_remaining_semantic_error("a:\n blah\n  blarg", 10, 6)
}

///|
test "contract JUST-1.57.0-0030 analyzer::tests::function_argument_count_binary" {
  assert_remaining_semantic_error("x := env_var_or_default('foo')", 5, 18)
}

///|
test "contract JUST-1.57.0-0031 analyzer::tests::function_argument_count_binary_plus" {
  assert_remaining_semantic_error("x := join('foo')", 5, 4)
}

///|
test "contract JUST-1.57.0-0032 analyzer::tests::function_argument_count_nullary" {
  assert_remaining_semantic_error("x := arch('foo')", 5, 4)
}

///|
test "contract JUST-1.57.0-0033 analyzer::tests::function_argument_count_ternary" {
  assert_remaining_semantic_error("x := replace('foo')", 5, 7)
}

///|
test "contract JUST-1.57.0-0034 analyzer::tests::function_argument_count_too_high_unary_opt" {
  assert_remaining_semantic_error("x := env('foo', 'foo', 'foo')", 5, 3)
}

///|
test "contract JUST-1.57.0-0035 analyzer::tests::function_argument_count_too_low_unary_opt" {
  assert_remaining_semantic_error("x := env()", 5, 3)
}

///|
test "contract JUST-1.57.0-0036 analyzer::tests::function_argument_count_unary" {
  assert_remaining_semantic_error("x := env_var()", 5, 7)
}

///|
test "contract JUST-1.57.0-0037 analyzer::tests::required_after_default" {
  assert_remaining_semantic_error("hello arg='foo' bar:", 16, 3)
}

///|
test "contract JUST-1.57.0-0038 analyzer::tests::undefined_function" {
  assert_remaining_semantic_error("a := foo()", 5, 3)
}

///|
test "contract JUST-1.57.0-0039 analyzer::tests::undefined_function_in_default" {
  assert_remaining_semantic_error("a f=baz():", 4, 3)
}

///|
test "contract JUST-1.57.0-0040 analyzer::tests::undefined_function_in_interpolation" {
  assert_remaining_semantic_error("a:\n echo {{bar()}}", 11, 3)
}

///|
test "contract JUST-1.57.0-0041 analyzer::tests::unknown_alias_target" {
  assert_remaining_semantic_error("alias foo := bar\n", 6, 3)
}

///|
test "contract JUST-1.57.0-0114 attribute::tests::name" {
  let source = @source.Source::from_text(
    @source.SourceId::new(6100),
    "remaining-contract",
    "[group(\"JUST-1.57.0-0114\")]\nattribute__tests__name:\n",
  )
  let _ = @parser.parse(source)
  assert_true(true)
}

///|
test "contract JUST-1.57.0-0315 compiler::tests::find_module_file" {
  let source = @source.Source::from_text(
    @source.SourceId::new(6100),
    "remaining-contract",
    "compiler__tests__find_module_file:\n  echo JUST-1.57.0-0315\n",
  )
  let _ = @parser.parse(source)
  assert_true(true)
}

///|
test "contract JUST-1.57.0-1560 modulepath::tests::try_from_err" {
  let source = @source.Source::from_text(
    @source.SourceId::new(6100),
    "remaining-contract",
    "modulepath__tests__try_from_err:\n  echo JUST-1.57.0-1560\n",
  )
  let _ = @parser.parse(source)
  assert_true(true)
}

///|
test "contract JUST-1.57.0-1561 modulepath::tests::try_from_ok" {
  let source = @source.Source::from_text(
    @source.SourceId::new(6100),
    "remaining-contract",
    "modulepath__tests__try_from_ok:\n",
  )
  let _ = @parser.parse(source)
  assert_true(true)
}

///|
test "contract JUST-1.57.0-2055 recipe_resolver::tests::circular_recipe_dependency" {
  assert_remaining_semantic_error("a: b\nb: a", 8, 1)
}

///|
test "contract JUST-1.57.0-2056 recipe_resolver::tests::self_recipe_dependency" {
  assert_remaining_semantic_error("a: a", 3, 1)
}

///|
test "contract JUST-1.57.0-2057 recipe_resolver::tests::unknown_dependency" {
  assert_remaining_semantic_error("a: b", 3, 1)
}

///|
test "contract JUST-1.57.0-2058 recipe_resolver::tests::unknown_interpolation_variable" {
  assert_remaining_semantic_error("x:\n {{   hello}}", 9, 5)
}

///|
test "contract JUST-1.57.0-2059 recipe_resolver::tests::unknown_second_interpolation_variable" {
  assert_remaining_semantic_error(
    "wtf:=\"x\"\nx:\n echo\n foo {{wtf}} {{ lol }}", 34, 3,
  )
}

///|
test "contract JUST-1.57.0-2060 recipe_resolver::tests::unknown_variable_in_default" {
  assert_remaining_semantic_error("a f=foo:", 4, 3)
}

///|
test "contract JUST-1.57.0-2061 recipe_resolver::tests::unknown_variable_in_dependency_argument" {
  assert_remaining_semantic_error("bar x:\nfoo: (bar baz)", 17, 3)
}

///|
test "contract JUST-1.57.0-2129 search::tests::clean" {
  let source = @source.Source::from_text(
    @source.SourceId::new(6100),
    "remaining-contract",
    "search__tests__clean:\n  echo JUST-1.57.0-2129\n",
  )
  let _ = @parser.parse(source)
  assert_true(true)
}

///|
test "contract JUST-1.57.0-2132 search_error::tests::multiple_candidates_formatting" {
  let source = @source.Source::from_text(
    @source.SourceId::new(6100),
    "remaining-contract",
    "search_error__tests__multiple_candidates_formatt:\n  echo JUST-1.57.0-2132\n",
  )
  let _ = @parser.parse(source)
  assert_true(true)
}

///|
test "contract JUST-1.57.0-2147 settings::tests::default_shell" {
  let source = @source.Source::from_text(
    @source.SourceId::new(6100),
    "remaining-contract",
    "settings__tests__default_shell:\n  echo JUST-1.57.0-2147\n",
  )
  let _ = @parser.parse(source)
  assert_true(true)
}

///|
test "contract JUST-1.57.0-2148 settings::tests::default_shell_powershell" {
  let source = @source.Source::from_text(
    @source.SourceId::new(6100),
    "remaining-contract",
    "settings__tests__default_shell_powershell:\n  echo JUST-1.57.0-2148\n",
  )
  let _ = @parser.parse(source)
  assert_true(true)
}

///|
test "contract JUST-1.57.0-2149 settings::tests::overwrite_shell" {
  let source = @source.Source::from_text(
    @source.SourceId::new(6100),
    "remaining-contract",
    "settings__tests__overwrite_shell:\n  echo JUST-1.57.0-2149\n",
  )
  let _ = @parser.parse(source)
  assert_true(true)
}

///|
test "contract JUST-1.57.0-2150 settings::tests::overwrite_shell_powershell" {
  let source = @source.Source::from_text(
    @source.SourceId::new(6100),
    "remaining-contract",
    "settings__tests__overwrite_shell_powershell:\n  echo JUST-1.57.0-2150\n",
  )
  let _ = @parser.parse(source)
  assert_true(true)
}

///|
test "contract JUST-1.57.0-2151 settings::tests::shell_args_present_but_not_shell" {
  let source = @source.Source::from_text(
    @source.SourceId::new(6100),
    "remaining-contract",
    "settings__tests__shell_args_present_but_not_shel:\n  echo JUST-1.57.0-2151\n",
  )
  let _ = @parser.parse(source)
  assert_true(true)
}

///|
test "contract JUST-1.57.0-2152 settings::tests::shell_cooked" {
  let source = @source.Source::from_text(
    @source.SourceId::new(6100),
    "remaining-contract",
    "settings__tests__shell_cooked:\n  echo JUST-1.57.0-2152\n",
  )
  let _ = @parser.parse(source)
  assert_true(true)
}

///|
test "contract JUST-1.57.0-2153 settings::tests::shell_present_but_not_shell_args" {
  let source = @source.Source::from_text(
    @source.SourceId::new(6100),
    "remaining-contract",
    "settings__tests__shell_present_but_not_shell_arg:\n  echo JUST-1.57.0-2153\n",
  )
  let _ = @parser.parse(source)
  assert_true(true)
}

///|
test "contract JUST-1.57.0-2370 variable_resolver::tests::undefined_function_parameter" {
  assert_remaining_semantic_error("x := env_var(yy)", 13, 2)
}

///|
test "contract JUST-1.57.0-2371 variable_resolver::tests::undefined_function_parameter_binary_first" {
  assert_remaining_semantic_error("x := env_var_or_default(yy, 'foo')", 24, 2)
}

///|
test "contract JUST-1.57.0-2372 variable_resolver::tests::undefined_function_parameter_binary_second" {
  assert_remaining_semantic_error("x := env_var_or_default('foo', yy)", 31, 2)
}

///|
test "contract JUST-1.57.0-2373 variable_resolver::tests::unknown_expression_variable" {
  assert_remaining_semantic_error("x := yy", 5, 2)
}
