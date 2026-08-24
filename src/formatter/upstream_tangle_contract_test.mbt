///|
fn canonical_tangle_source(source : @source.Source) -> String raise {
  let text = source.text()
  if text.is_empty() {
    return ""
  }
  let output = StringBuilder()
  let line_count = source.line_count()
  for line in 1..<=line_count {
    let value = source.line_text(line)
    if line == line_count && value.is_empty() && text.has_suffix("\n") {
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
fn assert_tangle_contract(
  text : String,
  expected : String,
  id : Int,
) -> Unit raise {
  let source = @source.Source::from_text(
    @source.SourceId::new(id),
    "upstream-tangle-contract.md",
    text,
  )
  assert_eq(canonical_tangle_source(tangle(source).source()), expected)
}

///|
test "contract JUST-1.57.0-2318 tangle::tests::blocks" {
  let inputs = [
    "", "foo", "foo\nbar\n", "# foo\n\n```just\nbar:\n echo bar\n```\nbaz\n", "```just\nfoo := 'bar'\n```\nbaz\n```just\nbob:\n echo {{ foo }}\n```\n",
    "```sh\nfoo\n```\n",
  ]
  let expected = [
    "", "\n", "\n\n", "\n\n\nbar:\n echo bar\n\n\n", "\nfoo := 'bar'\n\n\n\nbob:\n echo {{ foo }}\n\n",
    "\n\n\n",
  ]
  for index, input in inputs {
    assert_tangle_contract(input, expected[index], 2300 * 100 + index)
  }
}

///|
test "contract JUST-1.57.0-2319 tangle::tests::fences" {
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
    assert_tangle_contract(input, expected[index], 2301 * 100 + index)
  }
}

///|
test "contract JUST-1.57.0-2320 tangle::tests::info_strings" {
  let inputs = [
    "```just foo\nbar:\n```\n", "``` just\nfoo:\n```\n", "```justfile\nfoo\n```\n",
    "```JUST\nfoo\n```\n", "```just`\nfoo\n",
  ]
  let expected = ["\nbar:\n\n", "\nfoo:\n\n", "\n\n\n", "\n\n\n", "\n\n"]
  for index, input in inputs {
    assert_tangle_contract(input, expected[index], 2302 * 100 + index)
  }
}

///|
test "contract JUST-1.57.0-2321 tangle::tests::invisible" {
  let inputs = [
    "<!--\n```just\nfoo:\n```\n-->\n", "> ```just\n> foo:\n> ```\n", "- foo\n\n  ```just\n  bar:\n  ```\n",
  ]
  let expected = ["\n\n\n\n\n", "\n\n\n", "\n\n\n\n\n"]
  for index, input in inputs {
    assert_tangle_contract(input, expected[index], 2303 * 100 + index)
  }
}

///|
test "contract JUST-1.57.0-2322 tangle::tests::nested" {
  let inputs = [
    "~~~\n```just\nfoo\n```\n~~~\n", "````\n```just\nfoo\n```\n````\n", "```\n```just\nfoo\n",
  ]
  let expected = ["\n\n\n\n\n", "\n\n\n\n\n", "\n\n\n"]
  for index, input in inputs {
    assert_tangle_contract(input, expected[index], 2304 * 100 + index)
  }
}
