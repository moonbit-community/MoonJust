///|
fn parser_upstream_source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(891), "justfile", text)
}

///|
fn assert_justfile_parser_items(text : String, expected : Int32) -> Unit raise {
  let ast = try! parse(parser_upstream_source(text))
  assert_eq(ast.items().length(), expected)
}
