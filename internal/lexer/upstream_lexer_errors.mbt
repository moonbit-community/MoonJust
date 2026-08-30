///|
test "upstream lexer::tests::ampersand_eof" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "&",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0002")
      assert_eq(error.span().start_byte(), 1)
      assert_eq(error.span().length(), 0)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::ampersand_unexpected" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "&%",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0003")
      assert_eq(error.span().start_byte(), 1)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::bad_dedent" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "a\n foo\n   bar\n  baz",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0013")
      assert_eq(error.span().start_byte(), 14)
      assert_eq(error.span().length(), 2)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::mismatched_closing_brace" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "(]",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0008")
      assert_eq(error.span().start_byte(), 1)
      assert_eq(error.span().length(), 0)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::mixed_leading_whitespace_indent" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "a\n foo\n \tbar",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0012")
      assert_eq(error.span().start_byte(), 7)
      assert_eq(error.span().length(), 2)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::mixed_leading_whitespace_normal" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "a\n\t echo hello",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0012")
      assert_eq(error.span().start_byte(), 2)
      assert_eq(error.span().length(), 2)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::mixed_leading_whitespace_recipe" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "a:\n\t echo hello",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0012")
      assert_eq(error.span().start_byte(), 3)
      assert_eq(error.span().length(), 2)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::tokenize_space_then_tab" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "a:\n 0\n 1\n\t2\n",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0013")
      assert_eq(error.span().start_byte(), 9)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::tokenize_tabs_then_tab_space" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "a:\n\t\t0\n\t\t 1\n\t  2\n",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0012")
      assert_eq(error.span().start_byte(), 12)
      assert_eq(error.span().length(), 2)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::unclosed_interpolation_delimiter" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "a:\n echo {{ foo",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0011")
      assert_eq(error.span().start_byte(), 9)
      assert_eq(error.span().length(), 2)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::unclosed_parenthesis_in_interpolation" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "a:\n echo {{foo(}}",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0008")
      assert_eq(error.span().start_byte(), 15)
      assert_eq(error.span().length(), 0)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::unpaired_carriage_return" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "foo\rbar",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0006")
      assert_eq(error.span().start_byte(), 3)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::unterminated_backtick" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "`echo",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0010")
      assert_eq(error.span().start_byte(), 0)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::unterminated_interpolation" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "foo:\n echo {{\n  ",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0011")
      assert_eq(error.span().start_byte(), 11)
      assert_eq(error.span().length(), 2)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::unterminated_raw_string" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "r a='asdf",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0009")
      assert_eq(error.span().start_byte(), 4)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::unterminated_string" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "a = \"",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0009")
      assert_eq(error.span().start_byte(), 4)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}

///|
test "upstream lexer::tests::unterminated_string_with_escapes" {
  let source = @source.Source::from_text(
    @source.SourceId::new(870),
    "justfile",
    "a = \"\\n\\t\\r\\\"\\\\",
  )
  try lex(source) catch {
    error => {
      assert_eq(error.code(), "MJ-LEX-0009")
      assert_eq(error.span().start_byte(), 4)
      assert_eq(error.span().length(), 1)
    }
  } noraise {
    _ => fail("expected lexer error")
  }
}
