///|
fn formatter_behavior_source(id : Int, text : String) -> @source.Source {
  @source.Source::from_text(
    @source.SourceId::new(id),
    "formatter.behavior",
    text,
  )
}

///|
test "formatter errors and check results preserve structured diagnostics" {
  let invalid = formatter_behavior_source(9940, "run: (\n")
  try @formatter.format_source(invalid) catch {
    Parse(_) as error => {
      assert_eq(error.code(), "MJ-FMT-0001")
      assert_true(error.span() is Some(_))
      assert_eq((try! error.to_diagnostic(invalid)).code(), error.code())
    }
    error => fail("unexpected formatter parse error: \{Repr(error)}")
  } noraise {
    _ => fail("expected formatter parse error")
  }

  let custom : FormatterError = InvalidInput("invalid indentation")
  assert_eq(custom.code(), "MJ-FMT-0002")
  assert_eq(custom.message(), "invalid indentation")
  assert_eq(custom.span(), None)
  assert_eq(
    (try! custom.to_diagnostic(invalid)).primary().span(),
    invalid.eof_span(),
  )

  let clean = formatter_behavior_source(9941, "run:\n")
  let clean_check = @formatter.check_with_indentation(clean, "  ")
  assert_false(clean_check.changed())
  assert_eq(clean_check.formatted(), "run:\n")
  assert_eq(@formatter.diff(clean), "")

  let changed = formatter_behavior_source(9942, "run:\n echo ok\n")
  let rendered_diff = @formatter.diff(changed)
  assert_true(
    rendered_diff.has_prefix("--- justfile\n+++ justfile (formatted)\n"),
  )
  assert_true(rendered_diff.contains("    echo ok"))
}

///|
test "formatter behavior prints every expression operator and item family" {
  let source = formatter_behavior_source(
    9943,
    "#!/usr/bin/env just --justfile\n" +
    "\n\n" +
    "# comment\n" +
    "export EXPORTED := 'value' # exported\n" +
    "EAGER := 'now'\n" +
    "unexport OLD\n" +
    "logic := !false || true && 'a' == 'a'\n" +
    "compare := 'a' != 'b' && 'abc' =~ 'b' && 'abc' !~ 'z'\n" +
    "joined := (['a'] ++ ['b']) + ('x' / 'y')\n" +
    "choice := if false { 'no' } else if true { 'yes' } else { 'never' }\n" +
    "formatted := f'prefix {{uppercase(\"x\")}} suffix'\n" +
    "function(a, b) := a + b\n" +
    "[private]\n" +
    "alias short := run\n" +
    "set shell := ['sh', '-cu']\n" +
    "set export\n" +
    "import? 'optional.just'\n" +
    "[private]\n" +
    "mod? tools 'tools.just'\n" +
    "[doc('run'), arg('value', long, help='value'), metadata('owner')]\n" +
    "@run $value=('a' + 'b') *rest: dep (with 'one') *(many *['x']) && cleanup # tail\n" +
    "  @echo {{ value }}\n" +
    "  echo {{ rest }}\n" +
    "\n" +
    "dep:\nwith x:\nmany +x:\ncleanup:\n",
  )
  let formatted = @formatter.format_source(source)
  assert_true(formatted.contains("logic := !false || true && 'a' == 'a'"))
  assert_true(formatted.contains("@run $value=('a' + 'b') *rest:"))
  assert_true(formatted.contains("*(many *['x'])"))
  assert_true(formatted.contains("cleanup"))
  let reparsed = formatter_behavior_source(9944, formatted)
  assert_eq(@formatter.format_source(reparsed), formatted)
}
