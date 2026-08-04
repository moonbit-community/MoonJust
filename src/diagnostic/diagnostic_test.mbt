///|
fn fixture() -> (@source.SourceMap, @source.SourceId, @source.SourceId) raise @source.SourceError {
  let sources = @source.SourceMap::new()
  let main_id = @source.SourceId::new(1)
  let imported_id = @source.SourceId::new(2)
  sources.add(
    @source.Source::from_text(main_id, "justfile", "build:\n  echo 中🙂\n"),
  )
  sources.add(
    @source.Source::from_text(imported_id, "common.just", "set shell := []\n"),
  )
  (sources, main_id, imported_id)
}

///|
test "structured diagnostic renders stable color-free text" {
  let (sources, main_id, imported_id) = fixture()
  let diagnostic = @diagnostic.Diagnostic::new(
    "MJ-PARSE-0001",
    Error,
    "expected expression",
    @source.Span::new(main_id, 14, 17),
    "expression starts here",
  )
  diagnostic.add_secondary(
    @source.Span::new(imported_id, 4, 9),
    "setting declared here",
  )
  diagnostic.add_source_trace(imported_id, "imported while loading")
  diagnostic.add_note("recipe bodies are indentation-sensitive")
  diagnostic.set_help("add a value after the command")
  assert_eq(diagnostic.secondary().length(), 1)
  assert_eq(diagnostic.notes().length(), 1)
  let rendered = @diagnostic.render_text(diagnostic, sources)
  assert_eq(
    rendered, "error[MJ-PARSE-0001]: expected expression\n --> justfile:2:8\n  |\n2 |   echo 中🙂\n  |        ^ expression starts here\n --> common.just:1:5\n  |\n1 | set shell := []\n  |     ----- setting declared here\n  = source: imported while loading (common.just)\n  = note: recipe bodies are indentation-sensitive\n  = help: add a value after the command\n",
  )
  assert_false(rendered.contains("\u{001b}"))
}

///|
test "empty and multiline labels remain visible" {
  let sources = @source.SourceMap::new()
  let id = @source.SourceId::new(3)
  sources.add(@source.Source::from_text(id, "multi.just", "one\ntwo\nthree"))
  let empty = @diagnostic.Diagnostic::new(
    "MJ-INFO-0001",
    Info,
    "empty location",
    @source.Span::new(id, 0, 0),
    "point",
  )
  assert_true(@diagnostic.render_text(empty, sources).contains("| ^ point"))
  let multiline = @diagnostic.Diagnostic::new(
    "MJ-WARN-0001",
    Warning,
    "spans lines",
    @source.Span::new(id, 1, 9),
    "long construct",
  )
  assert_true(
    @diagnostic.render_text(multiline, sources).contains(
      "^^ long construct (continues to line 3)",
    ),
  )
}

///|
test "missing source and invalid spans are typed renderer errors" {
  let sources = @source.SourceMap::new()
  let id = @source.SourceId::new(4)
  let diagnostic = @diagnostic.Diagnostic::new(
    "MJ-LOAD-0001",
    Error,
    "missing source",
    @source.Span::new(id, 0, 0),
    "not loaded",
  )
  try @diagnostic.render_text(diagnostic, sources) catch {
    MissingSource(actual) => assert_eq(actual, id)
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing source")
  }
  let loaded = @source.Source::from_text(id, "short", "x")
  sources.add(loaded)
  let invalid = @diagnostic.Diagnostic::new(
    "MJ-LOAD-0002",
    Error,
    "bad range",
    @source.Span::new(id, 0, 2),
    "too long",
  )
  try @diagnostic.render_text(invalid, sources) catch {
    InvalidLabelSpan(source_id~, start_byte=0, end_byte=2) =>
      assert_eq(source_id, id)
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid label span")
  }
}

///|
test "ANSI escapes cannot enter diagnostic IR" {
  let id = @source.SourceId::new(5)
  try
    @diagnostic.Diagnostic::new(
      "MJ-TEST-0001",
      Error,
      "unsafe \u{001b}[31mmessage",
      @source.Span::new(id, 0, 0),
      "label",
    )
  catch {
    @diagnostic.AnsiEscapeInField(field="diagnostic.message") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected ANSI rejection")
  }
}
