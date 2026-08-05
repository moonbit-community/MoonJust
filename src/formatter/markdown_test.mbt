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

///|
test "phase 3 markdown corpus preserves CommonMark fence boundaries" {
  let text = "before\n```text\njust-not-selected: \n```\n" +
    "~~~just\nselected: \n    echo ok\n~~~\n" +
    "<!--\n```just\ncommented: \n```\n-->\n"
  let source = @source.Source::from_text(
    @source.SourceId::new(610),
    "markdown-corpus.md",
    text,
  )
  let tangled = try! tangle(source)
  assert_eq(tangled.selected_blocks(), 1)
  assert_true(tangled.source().text().contains("selected:"))
  assert_true(!tangled.source().text().contains("just-not-selected"))
}

///|
test "phase 3 markdown hardening rejects line and byte budgets" {
  let source = @source.Source::from_text(
    @source.SourceId::new(611),
    "large.md",
    "```just\nrecipe:\n```\n",
  )
  let limits = try! MarkdownLimits::new(2, source.length())
  try tangle(source, limits~) catch {
    LimitExceeded(_) => ()
    _ => fail("unexpected Markdown error")
  } noraise {
    _ => fail("expected Markdown line limit")
  }
}
