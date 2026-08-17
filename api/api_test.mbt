///|
test "public api checks formats and lists recipes without leaking internals" {
  let text =
    #|message := "ok"
    #|zeta:
    #|  echo {{message}}
    #|_hidden:
    #|  true
    #|[private]
    #|secret:
    #|  true
    #|alpha:
    #|  true
    #|
  check_source(text, source_name="example.just")
  assert_true(format_text(text, source_name="example.just").contains("zeta:"))
  assert_eq(recipe_names(text, source_name="example.just"), ["alpha", "zeta"])
}

///|
test "public api returns owned one-based diagnostics" {
  try check_source("foo: missing\n", source_name="example.just") catch {
    InvalidSource(diagnostics) => {
      assert_eq(diagnostics.length(), 1)
      let diagnostic = diagnostics[0]
      assert_eq(diagnostic.source_name(), "example.just")
      assert_true(!diagnostic.code().is_empty())
      assert_true(diagnostic.message().contains("missing"))
      assert_eq(diagnostic.start_line(), Some(1))
      assert_eq(diagnostic.start_column(), Some(6))
      assert_true(diagnostic.end_line() is Some(_))
      assert_true(diagnostic.end_column() is Some(_))
    }
  } noraise {
    _ => fail("invalid source was accepted")
  }
}

///|
test "public api converts syntax failures without exposing parser types" {
  try check_source("broken:\n {{\n", source_name="syntax.just") catch {
    InvalidSource(diagnostics) => {
      assert_eq(diagnostics.length(), 1)
      let diagnostic = diagnostics[0]
      assert_eq(diagnostic.source_name(), "syntax.just")
      assert_true(!diagnostic.code().is_empty())
      assert_true(!diagnostic.message().is_empty())
      assert_true(diagnostic.start_line() is Some(_))
      assert_true(diagnostic.start_column() is Some(_))
    }
  } noraise {
    _ => fail("syntactically invalid source was accepted")
  }
}
