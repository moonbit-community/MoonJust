///|
test "upstream parser::tests::set_export_implicit" {
  let ast = try! parse(parser_upstream_source("set export\n"))
  assert_eq(ast.semantic_key(), "setting:export=")
}

///|
test "upstream parser::tests::set_export_false" {
  let ast = try! parse(parser_upstream_source("set export := false\n"))
  assert_eq(ast.semantic_key(), "setting:export=bool:false")
}

///|
test "upstream parser::tests::set_quiet_implicit" {
  let ast = try! parse(parser_upstream_source("set quiet\n"))
  assert_eq(ast.semantic_key(), "setting:quiet=")
}

///|
test "upstream parser::tests::set_quiet_true" {
  let ast = try! parse(parser_upstream_source("set quiet := true\n"))
  assert_eq(ast.semantic_key(), "setting:quiet=bool:true")
}

///|
test "upstream parser::tests::set_working_directory" {
  let ast = try! parse(
    parser_upstream_source("set working-directory := 'foo'\n"),
  )
  assert_eq(ast.semantic_key(), "setting:working-directory=string:raw(foo)")
}

///|
test "upstream parser::tests::set_dotenv_load_true" {
  let ast = try! parse(parser_upstream_source("set dotenv-load := true\n"))
  assert_eq(ast.semantic_key(), "setting:dotenv-load=bool:true")
}

///|
test "upstream parser::tests::set_dotenv_load_false" {
  let ast = try! parse(parser_upstream_source("set dotenv-load := false\n"))
  assert_eq(ast.semantic_key(), "setting:dotenv-load=bool:false")
}

///|
test "upstream parser::tests::set_positional_arguments_true" {
  let ast = try! parse(
    parser_upstream_source("set positional-arguments := true\n"),
  )
  assert_eq(ast.semantic_key(), "setting:positional-arguments=bool:true")
}

///|
test "upstream parser::tests::set_no_cd" {
  let ast = try! parse(parser_upstream_source("set no-cd := true\n"))
  assert_eq(ast.semantic_key(), "setting:no-cd=bool:true")
}

///|
test "upstream parser::tests::set_allow_duplicate_recipes_implicit" {
  let ast = try! parse(parser_upstream_source("set allow-duplicate-recipes\n"))
  assert_eq(ast.semantic_key(), "setting:allow-duplicate-recipes=")
}

///|
test "upstream parser::tests::set_allow_duplicate_variables_implicit" {
  let ast = try! parse(
    parser_upstream_source("set allow-duplicate-variables\n"),
  )
  assert_eq(ast.semantic_key(), "setting:allow-duplicate-variables=")
}

///|
test "upstream parser::tests::set_dotenv_load_implicit" {
  let ast = try! parse(parser_upstream_source("set dotenv-load\n"))
  assert_eq(ast.semantic_key(), "setting:dotenv-load=")
}

///|
test "upstream parser::tests::set_export_true" {
  let ast = try! parse(parser_upstream_source("set export := true\n"))
  assert_eq(ast.semantic_key(), "setting:export=bool:true")
}

///|
test "upstream parser::tests::set_positional_arguments_false" {
  let ast = try! parse(
    parser_upstream_source("set positional-arguments := false\n"),
  )
  assert_eq(ast.semantic_key(), "setting:positional-arguments=bool:false")
}

///|
test "upstream parser::tests::set_positional_arguments_implicit" {
  let ast = try! parse(parser_upstream_source("set positional-arguments\n"))
  assert_eq(ast.semantic_key(), "setting:positional-arguments=")
}

///|
test "upstream parser::tests::set_quiet_false" {
  let ast = try! parse(parser_upstream_source("set quiet := false\n"))
  assert_eq(ast.semantic_key(), "setting:quiet=bool:false")
}

///|
test "upstream parser::tests::set_windows_powershell_false" {
  let ast = try! parse(
    parser_upstream_source("set windows-powershell := false\n"),
  )
  assert_eq(ast.semantic_key(), "setting:windows-powershell=bool:false")
}

///|
test "upstream parser::tests::set_windows_powershell_implicit" {
  let ast = try! parse(parser_upstream_source("set windows-powershell\n"))
  assert_eq(ast.semantic_key(), "setting:windows-powershell=")
}

///|
test "upstream parser::tests::set_windows_powershell_true" {
  let ast = try! parse(
    parser_upstream_source("set windows-powershell := true\n"),
  )
  assert_eq(ast.semantic_key(), "setting:windows-powershell=bool:true")
}

///|
test "upstream parser::tests::set_shell_no_arguments" {
  let ast = try! parse(parser_upstream_source("set shell := ['tclsh']\n"))
  guard ast.items()[0] is Setting(setting) else { fail("expected setting") }
  assert_eq(setting.name(), "shell")
  assert_eq(setting.value().unwrap().semantic_key(), "list:[string:raw(tclsh)]")
}

///|
test "upstream parser::tests::set_shell_with_one_argument" {
  let ast = try! parse(parser_upstream_source("set shell := ['bash', '-cu']\n"))
  guard ast.items()[0] is Setting(setting) else { fail("expected setting") }
  assert_eq(
    setting.value().unwrap().semantic_key(),
    "list:[string:raw(bash),string:raw(-cu)]",
  )
}

///|
test "upstream parser::tests::set_shell_with_two_arguments" {
  let ast = try! parse(
    parser_upstream_source("set shell := ['bash', '-cu', '-l']\n"),
  )
  guard ast.items()[0] is Setting(setting) else { fail("expected setting") }
  assert_eq(
    setting.value().unwrap().semantic_key(),
    "list:[string:raw(bash),string:raw(-cu),string:raw(-l)]",
  )
}

///|
test "upstream parser::tests::set_shell_no_arguments_trailing_comma" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(892),
      "justfile",
      "set shell := ['tclsh',]\n",
    ),
  )
  guard ast.items()[0] is Setting(setting) else { fail("expected setting") }
  assert_eq(setting.name(), "shell")
  assert_eq(setting.value().unwrap().semantic_key(), "list:[string:raw(tclsh)]")
}

///|
test "upstream parser::tests::set_shell_with_one_argument_trailing_comma" {
  let ast = try! parse(
    @source.Source::from_text(
      @source.SourceId::new(893),
      "justfile",
      "set shell := ['bash', '-cu',]\n",
    ),
  )
  guard ast.items()[0] is Setting(setting) else { fail("expected setting") }
  assert_eq(setting.name(), "shell")
  assert_eq(
    setting.value().unwrap().semantic_key(),
    "list:[string:raw(bash),string:raw(-cu)]",
  )
}

///|
test "upstream parser::tests::set_shell_no_arguments_cooked" {
  let ast = try! parse(parser_upstream_source("set shell := [\"tclsh\"]"))
  guard ast.items()[0] is Setting(setting) else { fail("expected setting") }
  assert_eq(setting.name(), "shell")
  assert_eq(
    setting.value().unwrap().semantic_key(),
    "list:[string:cooked(tclsh)]",
  )
}
