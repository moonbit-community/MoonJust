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
test "markdown tangle excludes nested, four-space, and commented fences" {
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
test "markdown tangle accepts zero through three leading spaces" {
  let source = @source.Source::from_text(
    @source.SourceId::new(38),
    "README.md",
    "```just\nzero:\n```\n" +
    " ```just\none:\n ```\n" +
    "  ~~~just\ntwo:\n  ~~~\n" +
    "   ```just\nthree:\n   ```\n" +
    "    ```just\nignored:\n    ```\n",
  )
  let result = @formatter.tangle(source)
  assert_eq(result.selected_blocks(), 4)
  assert_true(result.source().text().contains("zero:"))
  assert_true(result.source().text().contains("one:"))
  assert_true(result.source().text().contains("two:"))
  assert_true(result.source().text().contains("three:"))
  assert_false(result.source().text().contains("ignored:"))
}

///|
test "markdown tangle requires matching fence character and minimum length" {
  let source = @source.Source::from_text(
    @source.SourceId::new(39),
    "README.md",
    "```just\nrecipe:\n~~~\nstill selected\n````\n",
  )
  let result = @formatter.tangle(source)
  assert_eq(result.selected_blocks(), 1)
  assert_true(result.source().text().contains("still selected"))
}

///|
test "markdown corpus preserves CommonMark fence boundaries" {
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
test "markdown hardening rejects line and byte budgets" {
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

///|
fn visible_tangled_lines(text : String, id : Int) -> Array[String] {
  let source = @source.Source::from_text(
    @source.SourceId::new(id),
    "upstream.md",
    text,
  )
  let tangled = try! @formatter.tangle(source).source()
  let result : Array[String] = []
  for line in 1..<=tangled.line_count() {
    let value = try! tangled.line_text(line)
    if !value.trim().is_empty() {
      result.push(value)
    }
  }
  result
}

///|
test "markdown matches pinned upstream info string corpus" {
  assert_eq(
    visible_tangled_lines(
      "```just foo\none:\n```\n``` just\ntwo:\n```\n" +
      "```justfile\nignored\n```\n```JUST\nignored\n```\n```just`\nignored\n",
      1010,
    ),
    ["one:", "two:"],
  )
}

///|
test "markdown matches pinned upstream fence corpus" {
  assert_eq(
    visible_tangled_lines(
      "~~~just\ntilde:\n~~~\n``just\nignored\n" +
      "```just\nmatching:\n~~~\nstill-selected\n`````  \n" +
      "````just\nlong:\n```\nstill-long\n````\n" +
      "```just\nunclosed:\ncontinues\n",
      1011,
    ),
    [
      "tilde:", "matching:", "~~~", "still-selected", "long:", "```", "still-long",
      "unclosed:", "continues",
    ],
  )
}

///|
test "markdown rejects CommonMark nested and invisible blocks" {
  let text = "~~~~\n```just\nouter-fence:\n```\n~~~~\n" +
    "<!--\n```just\ncomment:\n```\n-->\n" +
    "> ```just\n> quote:\n> ```\n" +
    "- item\n\n  ```just\n  list:\n  ```\n" +
    "```just\ntop-level:\n```\n"
  assert_eq(visible_tangled_lines(text, 1012), ["top-level:"])
}
