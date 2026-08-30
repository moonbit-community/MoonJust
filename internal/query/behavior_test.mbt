///|
test "query summary filters private recipes and sorts names" {
  let source = @source.Source::from_text(
    @source.SourceId::new(708),
    "justfile",
    "zeta:\n[private]\nhidden:\nalpha:\n",
  )
  let compilation = try! @semantic.compile(try! @parser.parse(source))
  let request = build_query(try! @cli.parse_arguments(["--summary"], Map([])))
  assert_eq(visible_recipe_names(compilation, request), ["alpha", "zeta"])
}

///|
test "query model owns immutable rendered bytes" {
  let result = QueryResult::new(stdout=b"ok\n", stderr=b"warning\n")
  assert_eq(result.stdout(), b"ok\n")
  assert_eq(result.stderr(), b"warning\n")
}
