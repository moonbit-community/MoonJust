///|
test "markdown tangle selects direct just fences and preserves byte offsets" {
  let source = @source.Source::from_text(
    @source.SourceId::new(36),
    "README.md",
    "intro\n```just extra\nhello:\n  echo hi\n```\n```sh\nignored\n```\n",
  )
  let result = @formatter.tangle(source)
  assert_eq(result.selected_blocks(), 1)
  let tangled = result.source()
  assert_eq(tangled.line_count(), source.line_count())
  assert_eq(tangled.line_text(3), "hello:")
  assert_eq(tangled.line_text(4), "  echo hi")
  assert_eq(tangled.line_start(3), source.line_start(3))
}

///|
test "markdown tangle excludes nested, indented, and commented fences" {
  let source = @source.Source::from_text(
    @source.SourceId::new(37),
    "README.md",
    "````\n```just\nignored:\n```\n````\n    ```just\nignored:\n```\n<!--\n```just\nignored:\n```\n-->\n~~~just\nselected:\n~~~\n",
  )
  let result = @formatter.tangle(source)
  assert_eq(result.selected_blocks(), 1)
  assert_eq(result.source().line_text(15), "selected:")
}
