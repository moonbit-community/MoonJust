///|
test "upstream subcommand::tests::init_justfile" {
  let compilation = try! @semantic.compile_source(
    @source.Source::from_text(
      @source.SourceId::new(975),
      "justfile",
      INIT_TEMPLATE,
    ),
    allow_unstable=false,
  )
  assert_eq(compilation.recipe_names().to_owned(), ["default"])
  assert_eq(
    INIT_TEMPLATE,
    "# https://just.systems\n\ndefault:\n    echo 'Hello, world!'\n",
  )
}
