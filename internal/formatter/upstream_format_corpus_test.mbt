///|
fn upstream_format_source(text : String) -> String raise {
  @formatter.format_source(
    @source.Source::from_text(@source.SourceId::new(850), "justfile", text),
  )
}

///|
test "upstream format::adjacency_is_respected" {
  assert_eq(upstream_format_source("foo:\nbar:\n"), "foo:\nbar:\n")
}

///|
test "upstream format::alias_fix_indent" {
  assert_eq(
    upstream_format_source("alias f:=    foo\n\nfoo:\n    echo foo\n"),
    "alias f := foo\n\nfoo:\n    echo foo\n",
  )
}

///|
test "upstream format::alias_good" {
  assert_eq(
    upstream_format_source("alias f := foo\n\nfoo:\n    echo foo\n"),
    "alias f := foo\n\nfoo:\n    echo foo\n",
  )
}

///|
test "upstream format::arg_attribute_help" {
  assert_eq(
    upstream_format_source("[arg('bar', help='foo')]\n@foo bar:\n"),
    "[arg('bar', help='foo')]\n@foo bar:\n",
  )
}

///|
test "upstream format::arg_attribute_help_expression" {
  assert_eq(
    upstream_format_source("[arg('bar', help='f' + 'oo')]\n@foo bar:\n"),
    "[arg('bar', help='f' + 'oo')]\n@foo bar:\n",
  )
}

///|
test "upstream format::arg_attribute_long" {
  assert_eq(
    upstream_format_source("[arg('bar', long='bar')]\n@foo bar:\n"),
    "[arg('bar', long='bar')]\n@foo bar:\n",
  )
}

///|
test "upstream format::arg_attribute_long_and_pattern" {
  assert_eq(
    upstream_format_source(
      "[arg('bar', long='foo', pattern='baz')]\n@foo bar:\n",
    ),
    "[arg('bar', long='foo', pattern='baz')]\n@foo bar:\n",
  )
}

///|
test "upstream format::arg_attribute_long_bare" {
  assert_eq(
    upstream_format_source("[arg('bar', long)]\n@foo bar:\n"),
    "[arg('bar', long)]\n@foo bar:\n",
  )
}

///|
test "upstream format::arg_attribute_pattern" {
  assert_eq(
    upstream_format_source("[arg('bar', pattern='bar')]\n@foo bar:\n"),
    "[arg('bar', pattern='bar')]\n@foo bar:\n",
  )
}

///|
test "upstream format::arg_attribute_pattern_expression" {
  assert_eq(
    upstream_format_source("[arg('bar', pattern='b' + 'ar')]\n@foo bar:\n"),
    "[arg('bar', pattern='b' + 'ar')]\n@foo bar:\n",
  )
}

///|
test "upstream format::arg_attribute_short_bare" {
  assert_eq(
    upstream_format_source("[arg('bar', short)]\n@foo bar:\n"),
    "[arg('bar', short)]\n@foo bar:\n",
  )
}

///|
test "upstream format::arg_attribute_value" {
  assert_eq(
    upstream_format_source(
      "BAZ := 'baz'\n\n[arg('bar', long='bar', value=BAZ + env('FOO', 'foo'))]\n@foo bar:\n",
    ),
    "BAZ := 'baz'\n\n[arg('bar', long='bar', value=BAZ + env('FOO', 'foo'))]\n@foo bar:\n",
  )
}

///|
test "upstream format::assignment_backtick" {
  assert_eq(upstream_format_source("foo := `foo`\n"), "foo := `foo`\n")
}

///|
test "upstream format::assignment_binary_function" {
  assert_eq(
    upstream_format_source("foo := env_var_or_default('foo', 'bar')\n"),
    "foo := env_var_or_default('foo', 'bar')\n",
  )
}

///|
test "upstream format::assignment_concat_values" {
  assert_eq(
    upstream_format_source("foo := 'foo' + 'bar'\n"),
    "foo := 'foo' + 'bar'\n",
  )
}

///|
test "upstream format::assignment_doublequote" {
  assert_eq(upstream_format_source("foo := \"foo\"\n"), "foo := \"foo\"\n")
}

///|
test "upstream format::assignment_export" {
  assert_eq(
    upstream_format_source("export foo := 'foo'\n"),
    "export foo := 'foo'\n",
  )
}

///|
test "upstream format::assignment_if_multiline" {
  assert_eq(
    upstream_format_source(
      "foo := if 'foo' != 'foo' {\n  'foo'\n} else {\n  'bar'\n}\n",
    ),
    "foo := if 'foo' != 'foo' { 'foo' } else { 'bar' }\n",
  )
}

///|
test "upstream format::assignment_if_oneline" {
  assert_eq(
    upstream_format_source(
      "foo := if 'foo' == 'foo' { 'foo' } else { 'bar' }\n",
    ),
    "foo := if 'foo' == 'foo' { 'foo' } else { 'bar' }\n",
  )
}

///|
test "upstream format::assignment_indented_backtick" {
  assert_eq(
    upstream_format_source("foo := ```\n  foo\n```\n"),
    "foo := ```\n  foo\n```\n",
  )
}

///|
test "upstream format::assignment_indented_doublequote" {
  assert_eq(
    upstream_format_source("foo := \"\"\"\n  foo\n\"\"\"\n"),
    "foo := \"\"\"\n  foo\n\"\"\"\n",
  )
}

///|
test "upstream format::assignment_indented_singlequote" {
  assert_eq(
    upstream_format_source("foo := '''\n  foo\n'''\n"),
    "foo := '''\n  foo\n'''\n",
  )
}

///|
test "upstream format::assignment_name" {
  assert_eq(
    upstream_format_source("bar := 'bar'\nfoo := bar\n"),
    "bar := 'bar'\nfoo := bar\n",
  )
}

///|
test "upstream format::assignment_nullary_function" {
  assert_eq(upstream_format_source("foo := arch()\n"), "foo := arch()\n")
}

///|
test "upstream format::assignment_parenthesized_expression" {
  assert_eq(upstream_format_source("foo := ('foo')\n"), "foo := ('foo')\n")
}

///|
test "upstream format::assignment_path_functions" {
  assert_eq(
    upstream_format_source(
      "foo  := without_extension('foo/bar.baz')\nfoo2 := file_stem('foo/bar.baz')\nfoo3 := parent_directory('foo/bar.baz')\nfoo4 := file_name('foo/bar.baz')\nfoo5 := extension('foo/bar.baz')\n",
    ),
    "foo := without_extension('foo/bar.baz')\nfoo2 := file_stem('foo/bar.baz')\nfoo3 := parent_directory('foo/bar.baz')\nfoo4 := file_name('foo/bar.baz')\nfoo5 := extension('foo/bar.baz')\n",
  )
}

///|
test "upstream format::assignment_singlequote" {
  assert_eq(upstream_format_source("foo := 'foo'\n"), "foo := 'foo'\n")
}

///|
test "upstream format::assignment_unary_function" {
  assert_eq(
    upstream_format_source("foo := env_var('foo')\n"),
    "foo := env_var('foo')\n",
  )
}

///|
test "upstream format::comment" {
  assert_eq(upstream_format_source("# foo\n"), "# foo\n")
}

///|
test "upstream format::comment_before_docstring_recipe" {
  assert_eq(
    upstream_format_source("# bar\n\n# foo\nfoo:\n    echo foo\n"),
    "# bar\n\n# foo\nfoo:\n    echo foo\n",
  )
}

///|
test "upstream format::comment_before_recipe" {
  assert_eq(
    upstream_format_source("# foo\n\nfoo:\n    echo foo\n"),
    "# foo\n\nfoo:\n    echo foo\n",
  )
}

///|
test "upstream format::comment_leading" {
  assert_eq(
    upstream_format_source("# foo\n\nfoo := 'bar'\n"),
    "# foo\n\nfoo := 'bar'\n",
  )
}

///|
test "upstream format::comment_multiline" {
  assert_eq(upstream_format_source("# foo\n# bar\n"), "# foo\n# bar\n")
}

///|
test "upstream format::comment_trailing" {
  assert_eq(
    upstream_format_source("foo := 'bar'\n\n# foo\n"),
    "foo := 'bar'\n\n# foo\n",
  )
}

///|
test "upstream format::doc_attribute_expression" {
  assert_eq(
    upstream_format_source("[doc('f' + 'oo')]\nfoo:\n"),
    "[doc('f' + 'oo')]\nfoo:\n",
  )
}

///|
test "upstream format::doc_attribute_suppresses_comment" {
  assert_eq(
    upstream_format_source("# COMMENT\n[doc('ATTRIBUTE')]\nfoo:\n"),
    "# COMMENT\n[doc('ATTRIBUTE')]\nfoo:\n",
  )
}

///|
test "upstream format::empty_doc_comment_has_no_trailing_space" {
  assert_eq(upstream_format_source("#\nfoo:\n"), "#\nfoo:\n")
}

///|
test "upstream format::exported_parameter" {
  assert_eq(upstream_format_source("foo +$f:\n"), "foo +$f:\n")
}

///|
test "upstream format::first_line_shebang_is_not_a_doc_comment" {
  assert_eq(upstream_format_source("#!baz\nfoo:\n"), "#!baz\nfoo:\n")
}

///|
test "upstream format::if_else" {
  assert_eq(
    upstream_format_source(
      "x := if '' == '' { '' } else if '' == '' { '' } else { '' }\n",
    ),
    "x := if '' == '' { '' } else if '' == '' { '' } else { '' }\n",
  )
}

///|
test "upstream format::multi_argument_attribute" {
  assert_eq(
    upstream_format_source("[script('a', 'b', 'c')]\nfoo:\n"),
    "[script('a', 'b', 'c')]\nfoo:\n",
  )
}

///|
test "upstream format::multi_line_comments_before_recipes_are_not_broken_up" {
  assert_eq(
    upstream_format_source("# foo\n# bar\nbaz:\n"),
    "# foo\n# bar\nbaz:\n",
  )
}

///|
test "upstream format::multiple_newlines_between_items_are_collapsed" {
  assert_eq(upstream_format_source("foo:\n\n\nbar:\n"), "foo:\n\nbar:\n")
}

///|
test "upstream format::multiple_trailing_comments" {
  assert_eq(
    upstream_format_source("foo := 'bar' # comment1\nbaz := 'qux' # comment2\n"),
    "foo := 'bar' # comment1\nbaz := 'qux' # comment2\n",
  )
}

///|
test "upstream format::newline_after_recipe_with_body_is_preserved" {
  assert_eq(
    upstream_format_source("foo:\n    echo FOO\n\nbar:\n"),
    "foo:\n    echo FOO\n\nbar:\n",
  )
}

///|
test "upstream format::newlines_between_items_is_preserved" {
  assert_eq(upstream_format_source("foo:\n\nbar:\n"), "foo:\n\nbar:\n")
}

///|
test "upstream format::no_trailing_newline" {
  assert_eq(
    upstream_format_source("foo:\n    echo foo\n"),
    "foo:\n    echo foo\n",
  )
}

///|
test "upstream format::private_alias" {
  assert_eq(
    upstream_format_source("[private]\nalias f := foo\n\nfoo:\n    echo foo\n"),
    "[private]\nalias f := foo\n\nfoo:\n    echo foo\n",
  )
}

///|
test "upstream format::private_variable" {
  assert_eq(
    upstream_format_source("[private]\nfoo := 'bar'\n"),
    "[private]\nfoo := 'bar'\n",
  )
}

///|
test "upstream format::recipe_assignment_in_body" {
  assert_eq(
    upstream_format_source("bar := 'bar'\n\nfoo:\n    echo $bar\n"),
    "bar := 'bar'\n\nfoo:\n    echo $bar\n",
  )
}

///|
test "upstream format::recipe_body_is_comment" {
  assert_eq(upstream_format_source("foo:\n    # bar\n"), "foo:\n    # bar\n")
}

///|
test "upstream format::recipe_dependencies" {
  assert_eq(
    upstream_format_source(
      "bar:\n    echo bar\n\nbaz:\n    echo baz\n\nfoo: baz bar\n    echo foo\n",
    ),
    "bar:\n    echo bar\n\nbaz:\n    echo baz\n\nfoo: baz bar\n    echo foo\n",
  )
}

///|
test "upstream format::recipe_dependencies_params" {
  assert_eq(
    upstream_format_source(
      "bar BAR:\n    echo bar\n\nbaz BAZ:\n    echo baz\n\nfoo: (baz 'baz') (bar 'bar')\n    echo foo\n",
    ),
    "bar BAR:\n    echo bar\n\nbaz BAZ:\n    echo baz\n\nfoo: (baz 'baz') (bar 'bar')\n    echo foo\n",
  )
}

///|
test "upstream format::recipe_dependency" {
  assert_eq(
    upstream_format_source("bar:\n    echo bar\n\nfoo: bar\n    echo foo\n"),
    "bar:\n    echo bar\n\nfoo: bar\n    echo foo\n",
  )
}

///|
test "upstream format::recipe_dependency_param" {
  assert_eq(
    upstream_format_source(
      "bar BAR:\n    echo bar\n\nfoo: (bar 'bar')\n    echo foo\n",
    ),
    "bar BAR:\n    echo bar\n\nfoo: (bar 'bar')\n    echo foo\n",
  )
}

///|
test "upstream format::recipe_dependency_params" {
  assert_eq(
    upstream_format_source(
      "bar BAR BAZ:\n    echo bar\n\nfoo: (bar 'bar' 'baz')\n    echo foo\n",
    ),
    "bar BAR BAZ:\n    echo bar\n\nfoo: (bar 'bar' 'baz')\n    echo foo\n",
  )
}

///|
test "upstream format::recipe_escaped_braces" {
  assert_eq(
    upstream_format_source("foo BAR:\n    echo '{{{{BAR}}}}'\n"),
    "foo BAR:\n    echo '{{{{BAR}}}}'\n",
  )
}

///|
test "upstream format::recipe_ignore_errors" {
  assert_eq(
    upstream_format_source("foo:\n    -echo foo\n"),
    "foo:\n    -echo foo\n",
  )
}

///|
test "upstream format::recipe_ordinary" {
  assert_eq(
    upstream_format_source("foo:\n    echo bar\n"),
    "foo:\n    echo bar\n",
  )
}

///|
test "upstream format::recipe_parameter" {
  assert_eq(
    upstream_format_source("foo BAR:\n    echo foo\n"),
    "foo BAR:\n    echo foo\n",
  )
}

///|
test "upstream format::recipe_parameter_concat" {
  assert_eq(
    upstream_format_source("foo BAR=('bar' + 'baz'):\n    echo foo\n"),
    "foo BAR=('bar' + 'baz'):\n    echo foo\n",
  )
}

///|
test "upstream format::recipe_parameter_conditional" {
  assert_eq(
    upstream_format_source(
      "foo BAR:\n    echo {{ if 'foo' == 'foo' { 'foo' } else { 'bar' } }}\n",
    ),
    "foo BAR:\n    echo {{ if 'foo' == 'foo' { 'foo' } else { 'bar' } }}\n",
  )
}

///|
test "upstream format::recipe_parameter_default" {
  assert_eq(
    upstream_format_source("foo BAR='bar':\n    echo foo\n"),
    "foo BAR='bar':\n    echo foo\n",
  )
}

///|
test "upstream format::recipe_parameter_default_envar" {
  assert_eq(
    upstream_format_source("foo $BAR='foo':\n    echo foo\n"),
    "foo $BAR='foo':\n    echo foo\n",
  )
}

///|
test "upstream format::recipe_parameter_envar" {
  assert_eq(
    upstream_format_source("foo $BAR:\n    echo foo\n"),
    "foo $BAR:\n    echo foo\n",
  )
}

///|
test "upstream format::recipe_parameter_in_body" {
  assert_eq(
    upstream_format_source("foo BAR:\n    echo {{ BAR }}\n"),
    "foo BAR:\n    echo {{ BAR }}\n",
  )
}

///|
test "upstream format::recipe_parameters" {
  assert_eq(
    upstream_format_source("foo BAR BAZ:\n    echo foo\n"),
    "foo BAR BAZ:\n    echo foo\n",
  )
}

///|
test "upstream format::recipe_parameters_envar" {
  assert_eq(
    upstream_format_source("foo $BAR $BAZ:\n    echo foo\n"),
    "foo $BAR $BAZ:\n    echo foo\n",
  )
}

///|
test "upstream format::recipe_positional_variadic" {
  assert_eq(
    upstream_format_source("foo BAR *BAZ:\n    echo foo\n"),
    "foo BAR *BAZ:\n    echo foo\n",
  )
}

///|
test "upstream format::recipe_quiet" {
  assert_eq(
    upstream_format_source("@foo:\n    echo bar\n"),
    "@foo:\n    echo bar\n",
  )
}

///|
test "upstream format::recipe_quiet_command" {
  assert_eq(
    upstream_format_source("foo:\n    @echo bar\n"),
    "foo:\n    @echo bar\n",
  )
}

///|
test "upstream format::recipe_quiet_comment" {
  assert_eq(upstream_format_source("foo:\n    @# bar\n"), "foo:\n    @# bar\n")
}

///|
test "upstream format::recipe_several_commands" {
  assert_eq(
    upstream_format_source("foo:\n    echo bar\n    echo baz\n"),
    "foo:\n    echo bar\n    echo baz\n",
  )
}

///|
test "upstream format::recipe_variadic_default" {
  assert_eq(
    upstream_format_source("foo +BAR='bar':\n    echo foo\n"),
    "foo +BAR='bar':\n    echo foo\n",
  )
}

///|
test "upstream format::recipe_variadic_plus" {
  assert_eq(
    upstream_format_source("foo +BAR:\n    echo foo\n"),
    "foo +BAR:\n    echo foo\n",
  )
}

///|
test "upstream format::recipe_variadic_star" {
  assert_eq(
    upstream_format_source("foo *BAR:\n    echo foo\n"),
    "foo *BAR:\n    echo foo\n",
  )
}

///|
test "upstream format::recipe_with_comments_in_body" {
  assert_eq(
    upstream_format_source("foo:\n    # bar\n    echo bar\n"),
    "foo:\n    # bar\n    echo bar\n",
  )
}

///|
test "upstream format::recipe_with_docstring" {
  assert_eq(
    upstream_format_source("# bar\nfoo:\n    echo bar\n"),
    "# bar\nfoo:\n    echo bar\n",
  )
}

///|
test "upstream format::set_false" {
  assert_eq(
    upstream_format_source("set export := false\n"),
    "set export := false\n",
  )
}

///|
test "upstream format::set_shell" {
  assert_eq(
    upstream_format_source("set shell := ['sh', \"-c\"]\n"),
    "set shell := ['sh', \"-c\"]\n",
  )
}

///|
test "upstream format::set_true_explicit" {
  assert_eq(upstream_format_source("set export := true\n"), "set export\n")
}

///|
test "upstream format::set_true_implicit" {
  assert_eq(upstream_format_source("set export\n"), "set export\n")
}

///|
test "upstream format::subsequent" {
  assert_eq(
    upstream_format_source("bar:\n\nfoo: && bar\n    echo foo\n"),
    "bar:\n\nfoo: && bar\n    echo foo\n",
  )
}

///|
test "upstream format::trailing_comment_alias" {
  assert_eq(
    upstream_format_source("alias f := foo # baz\nfoo:\n"),
    "alias f := foo # baz\nfoo:\n",
  )
}

///|
test "upstream format::trailing_comment_assignment" {
  assert_eq(
    upstream_format_source("foo := 'bar' # baz\n"),
    "foo := 'bar' # baz\n",
  )
}

///|
test "upstream format::trailing_comment_bodyless_recipe" {
  assert_eq(upstream_format_source("foo: # bar\n"), "foo: # bar\n")
}

///|
test "upstream format::trailing_comment_does_not_become_doc_comment" {
  assert_eq(
    upstream_format_source("foo := 'bar' # baz\nqux:\n"),
    "foo := 'bar' # baz\nqux:\n",
  )
}

///|
test "upstream format::trailing_comment_export" {
  assert_eq(
    upstream_format_source("export foo := 'bar' # baz\n"),
    "export foo := 'bar' # baz\n",
  )
}

///|
test "upstream format::trailing_comment_recipe_with_body_is_stripped" {
  assert_eq(
    upstream_format_source("foo: # bar\n  echo baz\n"),
    "foo:\n    echo baz\n",
  )
}

///|
test "upstream format::trailing_comment_recipe_with_dependencies_and_body_is_stripped" {
  assert_eq(
    upstream_format_source("foo: bar # baz\n  echo qux\n\nbar:\n"),
    "foo: bar\n    echo qux\n\nbar:\n",
  )
}

///|
test "upstream format::trailing_comment_set" {
  assert_eq(upstream_format_source("set quiet # foo\n"), "set quiet # foo\n")
}

///|
test "upstream format::trailing_comment_unexport" {
  assert_eq(
    upstream_format_source("unexport FOO # bar\n"),
    "unexport FOO # bar\n",
  )
}

///|
test "upstream format::trailing_comments_separated_by_blank_line" {
  assert_eq(
    upstream_format_source(
      "foo := 'bar' # comment1\n\nbaz := 'qux' # comment2\n",
    ),
    "foo := 'bar' # comment1\n\nbaz := 'qux' # comment2\n",
  )
}
