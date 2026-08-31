///|
fn canonical_upstream_tangle(source : @source.Source) -> String raise {
  let text = source.text()
  if text.is_empty() {
    return ""
  }
  let output = StringBuilder()
  for line in 1..<=source.line_count() {
    let value = source.line_text(line)
    if line == source.line_count() && value.is_empty() && text.has_suffix("\n") {
      break
    }
    if !value.trim().is_empty() {
      output.write_string(value)
    }
    output.write_char('\n')
  }
  output.to_string()
}

///|
fn assert_upstream_tangle(
  input : String,
  expected : String,
  id : Int,
) -> Unit raise {
  let source = @source.Source::from_text(
    @source.SourceId::new(id),
    "upstream-tangle.md",
    input,
  )
  assert_eq(canonical_upstream_tangle(tangle(source).source()), expected)
}

///|
test "upstream tangle::tests::blocks" {
  let inputs = [
    "", "foo", "foo\nbar\n", "# foo\n\n```just\nbar:\n echo bar\n```\nbaz\n", "```just\nfoo := 'bar'\n```\nbaz\n```just\nbob:\n echo {{ foo }}\n```\n",
    "```sh\nfoo\n```\n",
  ]
  let expected = [
    "", "\n", "\n\n", "\n\n\nbar:\n echo bar\n\n\n", "\nfoo := 'bar'\n\n\n\nbob:\n echo {{ foo }}\n\n",
    "\n\n\n",
  ]
  for index, input in inputs {
    assert_upstream_tangle(input, expected[index], 9510 + index)
  }
}

///|
test "upstream tangle::tests::fences" {
  let inputs = [
    "~~~just\nfoo:\n~~~\n", "``just\nfoo\n", "  ```just\nfoo\n```\n", "```just\nfoo:\n```  \n",
    "```just\nfoo:\n`````\n", "```just\nfoo:\n~~~\nbar\n```\n", "````just\nfoo:\n```\n````\n",
    "```just\nfoo:\nbar\n",
  ]
  let expected = [
    "\nfoo:\n\n", "\n\n", "\n\n\n", "\nfoo:\n\n", "\nfoo:\n\n", "\nfoo:\n~~~\nbar\n\n",
    "\nfoo:\n```\n\n", "\nfoo:\nbar\n",
  ]
  for index, input in inputs {
    assert_upstream_tangle(input, expected[index], 9520 + index)
  }
}

///|
test "upstream tangle::tests::info_strings" {
  let inputs = [
    "```just foo\nbar:\n```\n", "``` just\nfoo:\n```\n", "```justfile\nfoo\n```\n",
    "```JUST\nfoo\n```\n", "```just`\nfoo\n",
  ]
  let expected = ["\nbar:\n\n", "\nfoo:\n\n", "\n\n\n", "\n\n\n", "\n\n"]
  for index, input in inputs {
    assert_upstream_tangle(input, expected[index], 9530 + index)
  }
}

///|
test "upstream tangle::tests::invisible" {
  let inputs = [
    "<!--\n```just\nfoo:\n```\n-->\n", "> ```just\n> foo:\n> ```\n", "- foo\n\n  ```just\n  bar:\n  ```\n",
  ]
  let expected = ["\n\n\n\n\n", "\n\n\n", "\n\n\n\n\n"]
  for index, input in inputs {
    assert_upstream_tangle(input, expected[index], 9540 + index)
  }
}

///|
test "upstream tangle::tests::nested" {
  let inputs = [
    "~~~\n```just\nfoo\n```\n~~~\n", "````\n```just\nfoo\n```\n````\n", "```\n```just\nfoo\n",
  ]
  let expected = ["\n\n\n\n\n", "\n\n\n\n\n", "\n\n\n"]
  for index, input in inputs {
    assert_upstream_tangle(input, expected[index], 9550 + index)
  }
}
