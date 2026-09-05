///|
fn upstream_script_recipe(text : String) -> @syntax.Recipe {
  let source = @source.Source::from_text(
    @source.SourceId::new(964),
    "justfile",
    text,
  )
  let compilation = try! @semantic.compile(try! @parser.parse(source))
  compilation.recipe("foo").unwrap()
}

///|
test "upstream script::shebang_line_numbers" {
  let recipe = upstream_script_recipe(
    "foo:\n  #!/usr/bin/env cat\n\n  a\n\n  b\n\n\n  c\n\n\n",
  )
  assert_eq(
    positioned_script_lines(
      recipe,
      ["#!/usr/bin/env cat", "", "a", "", "b", "", "", "c", "", ""],
      true,
    ),
    ["#!/usr/bin/env cat", "", "", "a", "", "b", "", "", "c"],
  )
}

///|
test "upstream script::multiline_shebang_line_numbers" {
  let recipe = upstream_script_recipe(
    "foo:\n  #!/usr/bin/env cat\n  #!shebang\n  #!shebang\n\n  a\n\n  b\n\n\n  c\n\n\n",
  )
  assert_eq(
    positioned_script_lines(
      recipe,
      [
        "#!/usr/bin/env cat", "#!shebang", "#!shebang", "", "a", "", "b", "", "",
        "c", "", "",
      ],
      true,
    ),
    [
      "#!/usr/bin/env cat", "#!shebang", "#!shebang", "", "", "a", "", "b", "", "",
      "c",
    ],
  )
}

///|
test "upstream script::script_line_numbers_with_multi_line_recipe_signature" {
  let recipe = upstream_script_recipe(
    "[script('cat')]\nfoo bar='baz' \\\n  :\n  FOO\n\n  BAR\n",
  )
  assert_eq(recipe.lines().length(), 3)
  for index, line in recipe.lines() {
    assert_true(line.source_start_line() >= 3)
    assert_true(line.source_end_line() >= line.source_start_line())
    if index > 0 {
      assert_true(
        line.source_start_line() >=
        recipe.lines()[index - 1].source_start_line(),
      )
    }
  }
}

///|
test "upstream script::shebang_line_numbers_with_multiline_constructs" {
  let recipe = upstream_script_recipe(
    "foo b='b'\\\n  :\n  #!/usr/bin/env cat\n\n  a\n\n  {{ b }}\n\n\n  c\n",
  )
  assert_eq(recipe.lines().length(), 8)
  for index, line in recipe.lines() {
    assert_true(line.source_start_line() >= 3)
    assert_true(line.source_end_line() >= line.source_start_line())
    if index > 0 {
      assert_true(
        line.source_start_line() >=
        recipe.lines()[index - 1].source_start_line(),
      )
    }
  }
}

///|
test "upstream script::script_line_numbers" {
  let recipe = upstream_script_recipe("[script('cat')]\nfoo:\n  FOO\n\n  BAR\n")
  assert_eq(recipe.lines().length(), 3)
  assert_eq(positioned_script_lines(recipe, ["FOO", "", "BAR"], false), [
    "", "", "FOO", "", "BAR",
  ])
}

///|
test "upstream script::use_final_path_component_of_script_interpreter_to_determine_shell_kind" {
  assert_eq(executable_name("/usr/local/bin/bash"), "bash")
  assert_eq(executable_name("C:\\tools\\bash.exe"), "bash.exe")
}

///|
test "upstream interpolation::shebang_line_numbers_are_correct_with_multi_line_interpolations" {
  let recipe = upstream_script_recipe(
    "foo:\n  #!/usr/bin/env cat\n  echo {{\n    'a'\n + 'b'\n        + 'c'\n  }}\n  echo foo\n",
  )
  assert_eq(recipe.lines().length(), 3)
  assert_true(
    recipe.lines()[0].source_start_line() <
    recipe.lines()[1].source_start_line(),
  )
  assert_true(
    recipe.lines()[1].source_end_line() >= recipe.lines()[1].source_start_line(),
  )
  assert_true(
    recipe.lines()[2].source_start_line() >
    recipe.lines()[1].source_start_line(),
  )
}

///|
test "upstream script::default_script_recipe_with_shebang_uses_shebang" {
  assert_eq(inferred_extension("cat"), "")
  assert_true(
    include_shebang_line("cat", @host.PlatformInfo::new(Linux, "test", Unix)),
  )
}

///|
test "upstream script::shebang_line_numbers_windows" {
  let platform = @host.PlatformInfo::new(Windows, "test", Windows)
  assert_false(include_shebang_line("cat", platform))
  assert_eq(inferred_extension("cmd.exe"), ".bat")
}

///|
test "upstream shebang::cmd" {
  assert_eq(inferred_extension("cmd"), ".bat")
  assert_false(needs_bom("cmd"))
}

///|
test "upstream shebang::cmd_exe" {
  assert_eq(inferred_extension("cmd.exe"), ".bat")
  assert_false(needs_bom("cmd.exe"))
}

///|
test "upstream shebang::multi_line_cmd_shebangs_are_removed" {
  let contents = @utf8.encode("#!/usr/bin/cmd\n#!second\necho ok\n")
  assert_eq(
    execution_script_contents(contents, true),
    @utf8.encode("\n\necho ok\n"),
  )
}

///|
test "upstream shebang::powershell" {
  assert_eq(inferred_extension("powershell"), ".ps1")
  assert_true(needs_bom("powershell"))
}

///|
test "upstream shebang::powershell_exe" {
  assert_eq(inferred_extension("powershell.exe"), ".ps1")
  assert_true(needs_bom("powershell.exe"))
}

///|
test "upstream shebang::powershell_utf8" {
  let contents = script_bytes(
    upstream_script_recipe("foo:\n  echo ok\n"),
    ["echo ok"],
    true,
    false,
    false,
  )
  assert_true(contents[0] == 0xef && contents[1] == 0xbb && contents[2] == 0xbf)
}
