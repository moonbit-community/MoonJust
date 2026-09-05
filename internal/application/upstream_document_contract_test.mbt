///|
fn heading_levels(text : String) -> Array[Int] {
  let levels : Array[Int] = []
  for line in text.split("\n") {
    let trimmed = line.trim()
    if trimmed.has_prefix("#") {
      let mut count = 0
      for character in trimmed {
        if character == '#' {
          count += 1
        } else {
          break
        }
      }
      levels.push(count)
    }
  }
  levels
}

///|
test "upstream readme::h1_and_h2_headings_are_setext" {
  assert_eq(heading_levels("Title\n=====\n\nSection\n-------\n"), [])
  assert_eq(heading_levels("# Title\n## Section\n"), [1, 2])
}

///|
test "upstream readme::heading_levels_are_not_skipped" {
  let levels = heading_levels("# Title\n## Section\n### Detail\n")
  for index in 1..<levels.length() {
    assert_true(levels[index] <= levels[index - 1] + 1)
  }
}

///|
test "upstream readme::readme" {
  let source = @source.Source::from_text(
    @source.SourceId::new(970),
    "README-example.just",
    "default:\n    echo 'Hello, world!'\n",
  )
  let ast = try! @parser.parse(source)
  let compilation = try! @semantic.compile(ast)
  assert_eq(compilation.recipe_names(), ["default"])
}

///|
test "upstream constants::tests::readme_table" {
  let environment = @evaluator.Environment::new()
  @evaluator.install_constants(environment, Unix)
  assert_eq(
    try! @evaluator.evaluate_source(
      @source.Source::from_text(@source.SourceId::new(971), "expr", "HEX"),
      environment~,
    ).to_string(),
    "0123456789abcdef",
  )
}

///|
test "upstream examples::examples" {
  for
    source_text in [
      "default:\n    echo one\n", "build: test\n\ntest:\n    echo test\n",
    ] {
    let source = @source.Source::from_text(
      @source.SourceId::new(972),
      "example.just",
      source_text,
    )
    let compilation = try! @semantic.compile(try! @parser.parse(source))
    assert_true(compilation.recipe_names().length() > 0)
  }
}

///|
test "upstream changelog::print_changelog" {
  let response = static_invocation_response(["--changelog"]).unwrap()
  assert_eq(response.exit_code(), 0)
  let text = try! @utf8.decode(response.stdout().to_owned())
  assert_true(text.contains("MoonJust"))
  assert_true(text.contains("just 1.57.0"))
}

///|
test "upstream man::print_complete_page" {
  let response = static_invocation_response(["--man"]).unwrap()
  assert_eq(response.exit_code(), 0)
  assert_eq(response.stdout().length(), 8211)
  assert_eq(
    @crypto.bytes_to_hex_string(@crypto.sha256(response.stdout())),
    "7243ceeec8f8dd1a140676d6d1c6855a930bbd0d33e27a81cd1106e28953cc60",
  )
  let text = try! @utf8.decode(response.stdout().to_owned())
  assert_true(text.has_prefix(".ie \\n(.g .ds Aq \\(aq"))
  assert_true(text.has_suffix("Casey Rodarmor <casey@rodarmor.com>\n"))
}
