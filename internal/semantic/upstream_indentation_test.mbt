///|
test "upstream indentation::tests::from_str_error" {
  for
    pair in [
      ("", "indentation must not be empty"),
      ("x", "indentation must be spaces or tabs"),
      (" \t", "indentation may not be mixed"),
    ] {
    let value = pair.0
    let expected_message = pair.1
    try
      @semantic.compile_source(
        @source.Source::from_text(
          @source.SourceId::new(912),
          "justfile",
          "set indentation := '" + value + "'\nfoo:\n",
        ),
        allow_unstable=true,
      )
    catch {
      InvalidIndentation(message~, span~) => {
        assert_eq(message, expected_message)
        assert_eq(
          span.length(),
          if value.is_empty() {
            2
          } else {
            value.length() + 2
          },
        )
      }
      error => fail("unexpected semantic error: \{Repr(error)}")
    } noraise {
      _ => fail("expected invalid indentation error")
    }
  }
}
