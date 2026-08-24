///|
fn contract_source(text : String) -> @source.Source {
  @source.Source::from_text(
    @source.SourceId::new(1700),
    "upstream-contract",
    text,
  )
}

///|
fn assert_contract(
  text : String,
  expect_error : Bool,
  expected_offset : Int,
  expected_width : Int,
) -> Unit raise {
  if !expect_error {
    let _ = parse(contract_source(text))
  } else {
    try parse(contract_source(text)) catch {
      error => {
        assert_eq(error.span().start_byte(), expected_offset)
        assert_eq(error.span().length(), expected_width)
      }
    } noraise {
      _ => fail("upstream parser contract unexpectedly succeeded")
    }
  }
}

///|
test "contract JUST-1.57.0-1825 parser::tests::addition_chained" {
  assert_contract("x := a + b + c", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1826 parser::tests::addition_single" {
  assert_contract("x := a + b", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1827 parser::tests::alias_equals" {
  assert_contract("alias t := test", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1828 parser::tests::alias_modulepath" {
  assert_contract("alias fbb := foo::bar::baz", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1829 parser::tests::alias_single" {
  assert_contract("alias t := test", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1830 parser::tests::alias_syntax_colon_end" {
  assert_contract("alias foo := bar::\n", true, 18, 1)
}

///|
test "contract JUST-1.57.0-1831 parser::tests::alias_syntax_multiple_rhs" {
  assert_contract("alias foo := bar baz", true, 17, 3)
}

///|
test "contract JUST-1.57.0-1832 parser::tests::alias_syntax_no_rhs" {
  assert_contract("alias foo := \n", true, 13, 1)
}

///|
test "contract JUST-1.57.0-1833 parser::tests::alias_syntax_single_colon" {
  assert_contract("alias foo := bar:baz", true, 16, 1)
}

///|
test "contract JUST-1.57.0-1834 parser::tests::alias_with_attribute" {
  assert_contract("[private]\nalias t := test", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1835 parser::tests::aliases_multiple" {
  assert_contract("alias t := test\nalias b := build", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1836 parser::tests::assert" {
  assert_contract("a := assert(b, \"error\")", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1837 parser::tests::assert_conditional_condition" {
  assert_contract(
    "foo := assert(if a { b } else { c }, \"error\")", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1838 parser::tests::assignment" {
  assert_contract("x := 'hello'", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1839 parser::tests::assignment_equals" {
  assert_contract("x := 'hello'", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1840 parser::tests::backtick" {
  assert_contract("x := `hello`", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1841 parser::tests::bad_export" {
  assert_contract("export a", true, 8, 0)
}

///|
test "contract JUST-1.57.0-1842 parser::tests::call_multiple_args" {
  assert_contract("x := env_var_or_default(y, z)", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1843 parser::tests::call_one_arg" {
  assert_contract("x := env_var(y)", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1844 parser::tests::call_trailing_comma" {
  assert_contract("x := env_var(y,)", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1845 parser::tests::comment" {
  assert_contract("# foo", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1846 parser::tests::comment_after_alias" {
  assert_contract("alias x := y # foo", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1847 parser::tests::comment_assignment" {
  assert_contract("x := y # foo", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1848 parser::tests::comment_before_alias" {
  assert_contract("# foo\nalias x := y", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1849 parser::tests::comment_export" {
  assert_contract("export x := y # foo", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1850 parser::tests::comment_recipe" {
  assert_contract("foo: # bar", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1851 parser::tests::comment_recipe_dependencies" {
  assert_contract("foo: bar # baz", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1852 parser::tests::comparison" {
  assert_contract("a := b == c", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1853 parser::tests::comparison_binds_looser_than_concatenation" {
  assert_contract("a := b + c == d + e", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1854 parser::tests::comparison_binds_tighter_than_logical_operators" {
  assert_contract("a := b == c && d == e || f == g", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1855 parser::tests::concatenation_in_default" {
  assert_contract("foo a=c+d e:", true, 10, 1)
}

///|
test "contract JUST-1.57.0-1856 parser::tests::concatenation_in_group" {
  assert_contract("x := ('0' + '1')", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1857 parser::tests::conditional" {
  assert_contract("a := if b { c } else { d }", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1858 parser::tests::conditional_concatenations" {
  assert_contract("a := if b0 + b1 { c0 + c1 } else { d0 + d1 }", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1859 parser::tests::conditional_inverted" {
  assert_contract("a := if b != c { d } else { e }", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1860 parser::tests::conditional_nested_lhs" {
  assert_contract(
    "a := if if b == c { d } else { e } == c { d } else { e }", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1861 parser::tests::conditional_nested_otherwise" {
  assert_contract(
    "a := if b { c } else { if d { e } else { f } }", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1862 parser::tests::conditional_nested_rhs" {
  assert_contract(
    "a := if c == if b == c { d } else { e } { d } else { e }", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1863 parser::tests::conditional_nested_then" {
  assert_contract(
    "a := if b { if c { d } else { e } } else { f }", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1864 parser::tests::conditional_without_otherwise" {
  assert_contract("a := if b { c }", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1865 parser::tests::doc_comment_assignment_clear" {
  assert_contract("# foo\nx := y\nbar:\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1866 parser::tests::doc_comment_empty_line_clear" {
  assert_contract("# foo\n\nbar:\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1867 parser::tests::doc_comment_middle" {
  assert_contract("bar:\n# foo\nbaz:\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1868 parser::tests::doc_comment_recipe_clear" {
  assert_contract("# foo\nbar:\nbaz:\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1869 parser::tests::doc_comment_single" {
  assert_contract("# foo\nbar:\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1870 parser::tests::double_negation" {
  assert_contract("a := !!b", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1871 parser::tests::empty" {
  assert_contract("", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1872 parser::tests::empty_attribute" {
  assert_contract("[]\nsome_recipe:\n @exit 3", true, 1, 1)
}

///|
test "contract JUST-1.57.0-1873 parser::tests::empty_body" {
  assert_contract("a:", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1874 parser::tests::empty_multiline" {
  assert_contract("\n\n\n\n\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1875 parser::tests::env_functions" {
  assert_contract(
    "x := env_var('foo',)\n\na:\n  {{env_var_or_default('foo' + 'bar', 'baz',)}} {{env_var(env_var('baz'))}}\n",
    false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1876 parser::tests::eof_test" {
  assert_contract("x:\ny:\nz:\na b c: x y z", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1877 parser::tests::escaped_dos_newlines" {
  assert_contract(
    "@spam:\r\n\t{ \\\r\n\t\tfiglet test; \\\r\n\t\tcargo build --color always 2>&1; \\\r\n\t\tcargo test  --color always -- --color always 2>&1; \\\r\n\t} | less\r\n",
    false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1878 parser::tests::export" {
  assert_contract("export x := 'hello'", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1879 parser::tests::export_equals" {
  assert_contract("export x := 'hello'", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1880 parser::tests::format_string_complex" {
  assert_contract(
    "foo := f'foo{{ 'abc' + 'xyz' }}bar{{ 'hello' }}goodbye'", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1881 parser::tests::format_string_expression" {
  assert_contract("foo := f'foo{{ 'abc' + 'xyz' }}bar'", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1882 parser::tests::format_string_simple" {
  assert_contract("foo := f'abc'", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1883 parser::tests::group" {
  assert_contract("x := (y)", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1884 parser::tests::import" {
  assert_contract("import \"some/file/path.txt\"     \n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1885 parser::tests::indented_backtick" {
  assert_contract("x := ```\n  \\tfoo\\t\n  \\tbar\\n\n```\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1886 parser::tests::indented_backtick_no_dedent" {
  assert_contract("x := ```\n\\tfoo\\t\n  \\tbar\\n\n```\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1887 parser::tests::indented_string_cooked" {
  assert_contract(
    "x := \"\"\"\n  \\tfoo\\t\n  \\tbar\\n\n\"\"\"\n", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1888 parser::tests::indented_string_cooked_no_dedent" {
  assert_contract(
    "x := \"\"\"\n\\tfoo\\t\n  \\tbar\\n\n\"\"\"\n", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1889 parser::tests::indented_string_raw_no_dedent" {
  assert_contract("x := '''\nfoo\\t\n  bar\\n\n'''\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1890 parser::tests::indented_string_raw_with_dedent" {
  assert_contract("x := '''\n  foo\\t\n  bar\\n\n'''\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1891 parser::tests::invalid_escape_sequence" {
  assert_contract("foo := \"\\b\"", true, 7, 4)
}

///|
test "contract JUST-1.57.0-1892 parser::tests::list_concatenation_single" {
  assert_contract("x := a ++ b", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1893 parser::tests::missing_colon" {
  assert_contract("a b c\nd e f", true, 5, 1)
}

///|
test "contract JUST-1.57.0-1894 parser::tests::missing_default_eof" {
  assert_contract("hello arg=", true, 10, 0)
}

///|
test "contract JUST-1.57.0-1895 parser::tests::missing_default_eol" {
  assert_contract("hello arg=\n", true, 10, 1)
}

///|
test "contract JUST-1.57.0-1896 parser::tests::missing_eol" {
  assert_contract("a b c: z =", true, 9, 1)
}

///|
test "contract JUST-1.57.0-1897 parser::tests::module_with" {
  assert_contract("mod foo", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1898 parser::tests::module_with_path" {
  assert_contract("mod foo \"some/file/path.txt\"     \n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1899 parser::tests::negation" {
  assert_contract("a := !b", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1900 parser::tests::negation_binds_tighter_than_comparison" {
  assert_contract("a := !b == c", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1901 parser::tests::optional_import" {
  assert_contract("import? \"some/file/path.txt\"     \n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1902 parser::tests::optional_module" {
  assert_contract("mod? foo", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1903 parser::tests::optional_module_with_path" {
  assert_contract("mod? foo \"some/file/path.txt\"     \n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1904 parser::tests::parameter_after_variadic" {
  assert_contract("foo +a bbb:", true, 7, 3)
}

///|
test "contract JUST-1.57.0-1905 parser::tests::parameter_default_backtick" {
  assert_contract("f x=`echo hello`:\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1906 parser::tests::parameter_default_concatenation_string" {
  assert_contract("f x=(`echo hello` + 'foo'):\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1907 parser::tests::parameter_default_concatenation_variable" {
  assert_contract(
    "x := '10'\n\nf y=(`echo hello` + x) +z='foo':\n", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1908 parser::tests::parameter_default_multiple" {
  assert_contract(
    "x := '10'\nf y=(`echo hello` + x) +z=('foo' + 'bar'):\n", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1909 parser::tests::parameter_default_raw_string" {
  assert_contract("f x='abc':\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1910 parser::tests::parameter_default_string" {
  assert_contract("f x='abc':\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1911 parser::tests::parameter_follows_variadic_parameter" {
  assert_contract("foo +a b:", true, 7, 1)
}

///|
test "contract JUST-1.57.0-1912 parser::tests::parameters" {
  assert_contract("a b c:\n  {{b}} {{c}}\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1913 parser::tests::parse_alias_after_target" {
  assert_contract("foo:\n  echo a\nalias f := foo\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1914 parser::tests::parse_alias_before_target" {
  assert_contract("alias f := foo\nfoo:\n  echo a\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1915 parser::tests::parse_alias_with_comment" {
  assert_contract("alias f := foo # comment\nfoo:\n  echo a\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1916 parser::tests::parse_assignment_backticks" {
  assert_contract(
    "a := `echo hello`\nc := a + b + a + b\nb := `echo goodbye`\n", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1917 parser::tests::parse_assignment_with_comment" {
  assert_contract("f := foo # comment\nfoo:\n  echo a\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1918 parser::tests::parse_assignments" {
  assert_contract("a := '0'\nc := a + b + a + b\nb := '1'\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1919 parser::tests::parse_complex" {
  assert_contract(
    "x:\ny:\nz:\nfoo := \"xx\"\nbar := foo\ngoodbye := \"y\"\nhello a b    c   : x y    z #hello\n  #! blah\n  #blarg\n  {{ foo + bar}}abc{{ goodbye\t  + \"x\" }}xyz\n  1\n  2\n  3\n",
    false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1920 parser::tests::parse_interpolation_backticks" {
  assert_contract(
    "a:\n  echo {{  `echo hello` + 'blarg'   }} {{   `echo bob`   }}\n", false, -1,
    -1,
  )
}

///|
test "contract JUST-1.57.0-1921 parser::tests::parse_raw_string_default" {
  assert_contract("\nfoo a='b\\t':\n\n\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1922 parser::tests::parse_shebang" {
  assert_contract(
    "practicum := 'hello'\ninstall:\n\t#!/bin/sh\n\tif [[ -f {{practicum}} ]]; then\n\t\treturn\n\tfi\n",
    false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1923 parser::tests::parse_simple_shebang" {
  assert_contract("a:\n #!\n  print(1)", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1924 parser::tests::plus_following_parameter" {
  assert_contract("a b c+:", true, 6, 1)
}

///|
test "contract JUST-1.57.0-1925 parser::tests::private_assignment" {
  assert_contract("[private]\nx := 'hello'\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1926 parser::tests::private_export" {
  assert_contract("[private]\nexport x := 'hello'\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1927 parser::tests::recipe" {
  assert_contract("foo:", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1928 parser::tests::recipe_default_multiple" {
  assert_contract("foo bar='baz' bob='biz':", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1929 parser::tests::recipe_default_single" {
  assert_contract("foo bar='baz':", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1930 parser::tests::recipe_dependency_argument_concatenation" {
  assert_contract("foo: (bar 'a' + 'b' 'c' + 'd')", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1931 parser::tests::recipe_dependency_argument_identifier" {
  assert_contract("foo: (bar baz)", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1932 parser::tests::recipe_dependency_argument_string" {
  assert_contract("foo: (bar 'baz')", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1933 parser::tests::recipe_dependency_module" {
  assert_contract("foo: bar::baz", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1934 parser::tests::recipe_dependency_module_mixed" {
  assert_contract("foo: bar::baz qux", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1935 parser::tests::recipe_dependency_multiple" {
  assert_contract("foo: bar baz", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1936 parser::tests::recipe_dependency_parenthesis" {
  assert_contract("foo: (bar)", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1937 parser::tests::recipe_dependency_parenthesis_module" {
  assert_contract("foo: (bar::baz)", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1938 parser::tests::recipe_dependency_single" {
  assert_contract("foo: bar", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1939 parser::tests::recipe_line_interpolation" {
  assert_contract("foo:\n bar{{\"bob\"}}biz", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1940 parser::tests::recipe_line_multiple" {
  assert_contract("foo:\n bar\n baz\n {{\"bob\"}}biz", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1941 parser::tests::recipe_line_single" {
  assert_contract("foo:\n bar", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1942 parser::tests::recipe_multiple" {
  assert_contract("foo:\nbar:\nbaz:\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1943 parser::tests::recipe_named_alias" {
  assert_contract("[private]\nalias:\n  echo 'echoing alias'\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1944 parser::tests::recipe_parameter_multiple" {
  assert_contract("foo bar baz:", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1945 parser::tests::recipe_parameter_single" {
  assert_contract("foo bar:", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1946 parser::tests::recipe_plus_variadic" {
  assert_contract("foo +bar:", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1947 parser::tests::recipe_quiet" {
  assert_contract("@foo:", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1948 parser::tests::recipe_star_variadic" {
  assert_contract("foo *bar:", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1949 parser::tests::recipe_subsequent" {
  assert_contract("foo: && bar", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1950 parser::tests::recipe_variadic_addition_group_default" {
  assert_contract("foo +bar=(baz + bob):", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1951 parser::tests::recipe_variadic_string_default" {
  assert_contract("foo +bar='baz':", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1952 parser::tests::recipe_variadic_variable_default" {
  assert_contract("foo +bar=baz:", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1953 parser::tests::recipe_variadic_with_default_after_default" {
  assert_contract("f a=b +c=d:\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1954 parser::tests::set_allow_duplicate_recipes_implicit" {
  assert_contract("set allow-duplicate-recipes", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1955 parser::tests::set_allow_duplicate_variables_implicit" {
  assert_contract("set allow-duplicate-variables", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1956 parser::tests::set_dotenv_load_false" {
  assert_contract("set dotenv-load := false", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1957 parser::tests::set_dotenv_load_implicit" {
  assert_contract("set dotenv-load", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1958 parser::tests::set_dotenv_load_true" {
  assert_contract("set dotenv-load := true", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1959 parser::tests::set_export_false" {
  assert_contract("set export := false", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1960 parser::tests::set_export_implicit" {
  assert_contract("set export", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1961 parser::tests::set_export_true" {
  assert_contract("set export := true", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1962 parser::tests::set_no_cd" {
  assert_contract("set no-cd := true", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1963 parser::tests::set_positional_arguments_false" {
  assert_contract("set positional-arguments := false", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1964 parser::tests::set_positional_arguments_implicit" {
  assert_contract("set positional-arguments", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1965 parser::tests::set_positional_arguments_true" {
  assert_contract("set positional-arguments := true", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1966 parser::tests::set_quiet_false" {
  assert_contract("set quiet := false", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1967 parser::tests::set_quiet_implicit" {
  assert_contract("set quiet", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1968 parser::tests::set_quiet_true" {
  assert_contract("set quiet := true", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1969 parser::tests::set_shell_bad" {
  assert_contract("set shell := ['bash'", true, 20, 0)
}

///|
test "contract JUST-1.57.0-1970 parser::tests::set_shell_bad_comma" {
  assert_contract("set shell := ['bash',", true, 21, 0)
}

///|
test "contract JUST-1.57.0-1971 parser::tests::set_shell_empty" {
  assert_contract("set shell := []", true, 14, 1)
}

///|
test "contract JUST-1.57.0-1972 parser::tests::set_shell_no_arguments" {
  assert_contract("set shell := ['tclsh']", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1973 parser::tests::set_shell_no_arguments_cooked" {
  assert_contract("set shell := [\"tclsh\"]", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1974 parser::tests::set_shell_no_arguments_trailing_comma" {
  assert_contract("set shell := ['tclsh',]", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1975 parser::tests::set_shell_with_one_argument" {
  assert_contract("set shell := ['bash', '-cu']", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1976 parser::tests::set_shell_with_one_argument_trailing_comma" {
  assert_contract("set shell := ['bash', '-cu',]", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1977 parser::tests::set_shell_with_two_arguments" {
  assert_contract("set shell := ['bash', '-cu', '-l']", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1978 parser::tests::set_unknown" {
  assert_contract("set shall := []", true, 4, 5)
}

///|
test "contract JUST-1.57.0-1979 parser::tests::set_windows_powershell_false" {
  assert_contract("set windows-powershell := false", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1980 parser::tests::set_windows_powershell_implicit" {
  assert_contract("set windows-powershell", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1981 parser::tests::set_windows_powershell_true" {
  assert_contract("set windows-powershell := true", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1982 parser::tests::set_working_directory" {
  assert_contract("set working-directory := 'foo'", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1983 parser::tests::single_argument_attribute_shorthand" {
  assert_contract("[group: 'foo']\nbar:", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1984 parser::tests::single_argument_attribute_shorthand_multiple_same_line" {
  assert_contract("[group: 'foo', group: 'bar']\nbaz:", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1985 parser::tests::single_line_body" {
  assert_contract("a:\n foo", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1986 parser::tests::string_escape_carriage_return" {
  assert_contract("x := \"foo\\rbar\"", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1987 parser::tests::string_escape_newline" {
  assert_contract("x := \"foo\\nbar\"", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1988 parser::tests::string_escape_quote" {
  assert_contract("x := \"foo\\\"bar\"", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1989 parser::tests::string_escape_slash" {
  assert_contract("x := \"foo\\\\bar\"", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1990 parser::tests::string_escape_suppress_newline" {
  assert_contract("x := \"foo\\\nbar\"\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1991 parser::tests::string_escape_tab" {
  assert_contract("x := \"foo\\tbar\"", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1992 parser::tests::string_escapes" {
  assert_contract("a := \"\\n\\t\\r\\\"\\\\\"", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1993 parser::tests::string_in_group" {
  assert_contract("x := ('0'   )", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1994 parser::tests::string_quote_escape" {
  assert_contract("a := \"hello\\\"\"", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1995 parser::tests::trimmed_body" {
  assert_contract("a:\n foo\n\n\n\nb:\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1996 parser::tests::unary_functions" {
  assert_contract(
    "x := arch()\n\na:\n  {{os()}} {{os_family()}}\n", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1997 parser::tests::unclosed_parenthesis_in_expression" {
  assert_contract("x := foo(", true, 9, 0)
}

///|
test "contract JUST-1.57.0-1998 parser::tests::unexpected_brace" {
  assert_contract("{{", true, 0, 1)
}

///|
test "contract JUST-1.57.0-1999 parser::tests::unknown_attribute" {
  assert_contract("[unknown]\nsome_recipe:\n @exit 3", true, 1, 7)
}

///|
test "contract JUST-1.57.0-2000 parser::tests::variable" {
  assert_contract("x := y", false, -1, -1)
}

///|
test "contract JUST-1.57.0-2001 parser::tests::whitespace" {
  assert_contract("", false, -1, -1)
}
