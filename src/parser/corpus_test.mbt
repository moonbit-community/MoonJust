///|
fn corpus_source(id : Int, text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(id), "upstream-corpus", text)
}

///|
fn parser_error(text : String) -> Bool {
  try @parser.parse(corpus_source(700, text)) catch {
    _ => true
  } noraise {
    _ => false
  }
}

///|
test "phase 3 grammar corpus covers every registered setting and attribute" {
  let mut id = 710
  for name in @parser.setting_names() {
    let value = match name {
      "minimum-version" => "\"1.57.0\""
      "indentation" => "\"    \""
      "script-interpreter" | "shell" | "tempdir" => "\"sh\""
      "default-list"
      | "default-script"
      | "dotenv-command"
      | "dotenv-filename"
      | "dotenv-path" => "\"justfile\""
      _ => ""
    }
    let source = if value == "" {
      "set " + name + "\nrecipe-" + id.to_string() + ":\n"
    } else {
      "set " + name + " := " + value + "\nrecipe-" + id.to_string() + ":\n"
    }
    let ast = @parser.parse(corpus_source(id, source))
    assert_true(ast.items().length() >= 2)
    id += 1
  }
  for name in @parser.attribute_names() {
    let attribute = match name {
      "extension" | "group" | "metadata" | "working-directory" =>
        "[" + name + "(\"value\")]\n"
      "env" => "[env(\"NAME\", \"value\")]\n"
      "arg" => "[arg(\"value\", long=\"value\")]\n"
      "cache" => "[cache(inputs=\"value\")]\n"
      "continue" | "script" => "[" + name + "(\"value\")]\n"
      _ => "[" + name + "]\n"
    }
    let ast = @parser.parse(
      corpus_source(id, attribute + "recipe-" + id.to_string() + ":\n"),
    )
    assert_true(
      match ast.items()[0] {
        Recipe(recipe) => recipe.attributes().length() == 1
        _ => false
      },
    )
    id += 1
  }
}

///|
test "phase 3 grammar corpus rejects invalid attribute arity and unknown names" {
  assert_true(parser_error("[private(\"unexpected\")]\nrecipe:\n"))
  assert_true(parser_error("[extension]\nrecipe:\n"))
  assert_true(parser_error("[group(\"a\", \"b\")]\nrecipe:\n"))
  assert_true(parser_error("[env(\"NAME\")]\nrecipe:\n"))
  assert_true(parser_error("[cache(\"positional\")]\nrecipe:\n"))
  assert_true(parser_error("[arg(\"x\", unknown=\"y\")]\nrecipe x:\n"))
  assert_true(parser_error("[not-a-just-attribute]\nrecipe:\n"))
  assert_true(parser_error("set not-a-just-setting\nrecipe:\n"))
}

///|
test "phase 3 parser recovery preserves error locations and later items" {
  let source = corpus_source(
    701, "set not-a-setting\n[private(\"bad\")]\nbuild:\nvalid:\n",
  )
  let report = @parser.parse_recovering(source)
  assert_eq(report.errors().length(), 2)
  assert_true(report.errors()[0] is UnknownSetting(name="not-a-setting", ..))
  assert_true(report.errors()[1] is InvalidAttributeArity(name="private", ..))
  assert_eq(source.locate(report.errors()[0].span().start_byte()).line(), 1)
  assert_eq(source.locate(report.errors()[1].span().start_byte()).line(), 2)
  assert_true(
    report
    .ast()
    .items()
    .iter()
    .any(fn(item) { item is Recipe(recipe) && recipe.name() == "valid" }),
  )
}

///|
fn next_random(state : Int) -> Int {
  (state * 1103515245 + 12345) & 0x7fffffff
}

///|
test "phase 3 parser fuzz corpus never escapes through an uncontrolled panic" {
  let alphabet = "abcxyz0123 :=()[]{}\"'\\n,+*/!?&|#@$"
  let mut state = 17
  for index in 0..<10_000 {
    let mut text = ""
    let length = state % 48
    for _ in 0..<length {
      state = next_random(state)
      let character = alphabet[state % alphabet.length()]
      text += character.to_string()
    }
    state = next_random(state)
    try @parser.parse(corpus_source(900 + index, text)) catch {
      _ => ()
    } noraise {
      _ => fail("parser fuzz escaped through a panic")
    }
  }
}
