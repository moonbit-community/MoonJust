///|
test "upstream parser::tests::alias_syntax_colon_end" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "alias foo := bar::\n",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0001")
      assert_eq(error.span().start_byte(), 18)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::alias_syntax_multiple_rhs" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "alias foo := bar baz",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0001")
      assert_eq(error.span().start_byte(), 17)
      assert_eq(error.span().length(), 3)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::alias_syntax_no_rhs" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "alias foo := \n",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0001")
      assert_eq(error.span().start_byte(), 13)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::alias_syntax_single_colon" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "alias foo := bar:baz",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0001")
      assert_eq(error.span().start_byte(), 16)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::bad_export" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "export a",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0001")
      assert_eq(error.span().start_byte(), 8)
      assert_eq(error.span().length(), 0)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::empty_attribute" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "[]\nsome_recipe:\n @exit 3",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0001")
      assert_eq(error.span().start_byte(), 1)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::invalid_escape_sequence" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "foo := \"\\b\"",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0002")
      assert_eq(error.span().start_byte(), 7)
      assert_eq(error.span().length(), 4)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::missing_colon" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "a b c\nd e f",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0001")
      assert_eq(error.span().start_byte(), 5)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::missing_default_eof" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "hello arg=",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0001")
      assert_eq(error.span().start_byte(), 10)
      assert_eq(error.span().length(), 0)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::missing_default_eol" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "hello arg=\n",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0001")
      assert_eq(error.span().start_byte(), 10)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::missing_eol" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "a b c: z =",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0001")
      assert_eq(error.span().start_byte(), 9)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::plus_following_parameter" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "a b c+:",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0001")
      assert_eq(error.span().start_byte(), 6)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::set_shell_bad" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "set shell := ['bash'",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0001")
      assert_eq(error.span().start_byte(), 20)
      assert_eq(error.span().length(), 0)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::set_shell_bad_comma" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "set shell := ['bash',",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0001")
      assert_eq(error.span().start_byte(), 21)
      assert_eq(error.span().length(), 0)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::set_shell_empty" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "set shell := []",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0001")
      assert_eq(error.span().start_byte(), 14)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::set_unknown" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "set shall := []",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0004")
      assert_eq(error.span().start_byte(), 4)
      assert_eq(error.span().length(), 5)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::unclosed_parenthesis_in_expression" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "x := foo(",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0001")
      assert_eq(error.span().start_byte(), 9)
      assert_eq(error.span().length(), 0)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::unexpected_brace" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "{{",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0001")
      assert_eq(error.span().start_byte(), 0)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}

///|
test "upstream parser::tests::unknown_attribute" {
  let source = @source.Source::from_text(
    @source.SourceId::new(880),
    "justfile",
    "[unknown]\nsome_recipe:\n @exit 3",
  )
  try parse(source) catch {
    error => {
      assert_eq(error.code(), "MJ-PARSE-0006")
      assert_eq(error.span().start_byte(), 1)
      assert_eq(error.span().length(), 7)
    }
  } noraise {
    _ => fail("expected parser error")
  }
}
