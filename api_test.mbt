///|
test "root facade exposes parse format compile and pure evaluate" {
  let source = @source.Source::from_text(
    @source.SourceId::new(60),
    "justfile",
    "message := \"ok\"\nshow:\n  echo {{message}}\n",
  )
  let ast = try! parse(source)
  assert_eq(ast.items().length(), 2)
  assert_true(format_source(source).contains("show:"))
  let compilation = try! compile_source(source)
  assert_eq(compilation.recipe_names(), ["show"])
  let expression = try! @parser.parse_expression(
    @source.Source::from_text(@source.SourceId::new(61), "expr", "true"),
  )
  assert_eq(evaluate_expression(expression), Bool(true))
}
