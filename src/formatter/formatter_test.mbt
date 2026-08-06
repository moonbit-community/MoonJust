///|
fn formatter_source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(35), "justfile", text)
}

///|
test "formatter is idempotent and canonicalizes recipe indentation" {
  let source = formatter_source("foo:\n  echo hi\n")
  let once = @formatter.format_source(source)
  assert_eq(once, "foo:\n    echo hi\n")
  let twice = @formatter.format_source(formatter_source(once))
  assert_eq(twice, once)
  assert_true(@formatter.is_formatted(formatter_source(once)))
  assert_true(@formatter.check(source).changed())
}

///|
test "formatter preserves expression structure and attributes" {
  let source = formatter_source("[private]\nfoo x: echo\ncollect *items:\n")
  let rendered = @formatter.format_source(source)
  assert_eq(rendered, "[private]\nfoo x: echo\ncollect *items:\n")
}

///|
test "phase 3 formatter corpus is idempotent across representative grammar" {
  let cases = [
    "x := if true { \"a\" + \"b\" } else { \"c\" }\n", "[doc(\"build\")]\nbuild:\n    echo {{\"ok\"}}\n",
    "set allow-duplicate-recipes\nimport? \"common.just\"\n", "f := f'hello {{name}}!'\n",
  ]
  for index, text in cases {
    let source = @source.Source::from_text(
      @source.SourceId::new(800 + index),
      "formatter-corpus",
      text,
    )
    let formatted = @formatter.format_source(source)
    let reparsed = @source.Source::from_text(
      @source.SourceId::new(900 + index),
      "formatter-corpus-formatted",
      formatted,
    )
    assert_eq(@formatter.format_source(reparsed), formatted)
  }
}

///|
test "formatter preserves the complete semantic AST model" {
  let source = formatter_source(
    "export greeting := f'hello {name}'\n" +
    "[doc(\"build\"), group(\"ci\")]\n" +
    "build name +rest: deploy name && cleanup\n" +
    "  @echo {{name}}\n" +
    "set shell := [\"sh\", \"-cu\"]\n" +
    "import? \"common.just\"\n" +
    "mod? tools \"tools.just\"\n",
  )
  let original = try! @parser.parse(source)
  let formatted = @formatter.format_source(source)
  let reparsed = try! @parser.parse(formatter_source(formatted))
  assert_eq(original.semantic_key(), reparsed.semantic_key())
}
