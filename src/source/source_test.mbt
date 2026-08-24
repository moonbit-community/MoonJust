///|
test "ASCII source and half-open spans" {
  let id = @source.SourceId::new(7)
  let source = @source.Source::from_text(id, "justfile", "alpha\nbeta")
  assert_eq(source.id(), id)
  assert_eq(source.name(), "justfile")
  assert_eq(source.length(), 10)
  assert_eq(source.line_count(), 2)
  assert_eq(source.line_start(1), 0)
  assert_eq(source.line_start(2), 6)
  assert_eq(source.line_text(1), "alpha")
  assert_eq(source.line_text(2), "beta")
  let span = @source.Span::new(id, 1, 5)
  assert_eq(source.slice_text(span), "lpha")
  assert_eq(span.length(), 4)
  assert_true(span.contains(1))
  assert_false(span.contains(5))
  assert_eq(source.slice_bytes(span).to_owned(), b"lpha")
}

///|
test "multibyte offsets and scalar columns" {
  let source = @source.Source::from_text(
    @source.SourceId::new(1),
    "unicode.just",
    "a中🙂é",
  )
  assert_eq(source.length(), 11)
  let boundaries = [(0, 0), (1, 1), (4, 2), (8, 3), (9, 4), (11, 5)]
  for pair in boundaries {
    let (offset, expected_scalar) = pair
    let position = source.locate(offset)
    assert_eq(position.line(), 1)
    assert_eq(position.byte_column(), offset)
    assert_eq(position.scalar_column(), expected_scalar)
  }
  for offset in [2, 3, 5, 6, 7, 10] {
    try source.locate(offset) catch {
      InvalidUtf8Boundary(offset=actual) => assert_eq(actual, offset)
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("expected an invalid UTF-8 boundary")
    }
  }
}

///|
test "CRLF, LF, and trailing empty line" {
  let source = @source.Source::from_text(
    @source.SourceId::new(2),
    "lines.just",
    "one\r\ntwo\nthree\r\n",
  )
  assert_eq(source.line_count(), 4)
  assert_eq(
    [
      source.line_start(1),
      source.line_start(2),
      source.line_start(3),
      source.line_start(4),
    ],
    [0, 5, 9, 16],
  )
  assert_eq(source.line_text(1), "one")
  assert_eq(source.line_text(2), "two")
  assert_eq(source.line_text(3), "three")
  assert_eq(source.line_text(4), "")
  let eof = source.locate(source.length())
  assert_eq(eof.line(), 4)
  assert_eq(eof.byte_column(), 0)
  assert_true(source.eof_span().is_empty())
}

///|
test "empty source has a valid EOF on line one" {
  let source = @source.Source::from_text(@source.SourceId::new(3), "empty", "")
  assert_eq(source.line_count(), 1)
  assert_eq(source.line_text(1), "")
  assert_eq(source.locate(0).line(), 1)
  assert_eq(source.full_span(), source.eof_span())
}

///|
test "invalid UTF-8 reports its byte offset" {
  try
    @source.Source::from_bytes(
      @source.SourceId::new(4),
      "invalid",
      b"ok\xfftail",
    )
  catch {
    InvalidUtf8(offset~) => assert_eq(offset, 2)
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid UTF-8")
  }
}

///|
test "span validation rejects bad bounds and source identity" {
  let first = @source.SourceId::new(5)
  let second = @source.SourceId::new(6)
  let source = @source.Source::from_text(first, "first", "abc")
  try @source.Span::new(first, 2, 1) catch {
    InvalidSpan(start_byte=2, end_byte=1) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid span")
  }
  let wrong = @source.Span::new(second, 0, 1)
  try source.slice_text(wrong) catch {
    WrongSource(expected~, actual~) => {
      assert_eq(expected, first)
      assert_eq(actual, second)
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected wrong source")
  }
  let too_long = @source.Span::new(first, 0, 4)
  try source.slice_text(too_long) catch {
    OffsetOutOfBounds(offset=4, length=3) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected out-of-bounds span")
  }
}

///|
test "span cover requires adjacency and matching source" {
  let id = @source.SourceId::new(8)
  let combined = @source.Span::new(id, 0, 2).cover(@source.Span::new(id, 2, 5))
  assert_eq(combined.start_byte(), 0)
  assert_eq(combined.end_byte(), 5)
  assert_eq(combined.at_end(), @source.Span::new(id, 5, 5))
  try @source.Span::new(id, 0, 1).cover(@source.Span::new(id, 2, 3)) catch {
    DisjointSpans(first_start=0, first_end=1, second_start=2, second_end=3) =>
      ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected disjoint spans")
  }
}

///|
test "source map rejects duplicates and missing IDs" {
  let sources = @source.SourceMap::new()
  let id = @source.SourceId::new(9)
  let source = @source.Source::from_text(id, "mapped", "x")
  sources.add(source)
  assert_eq(sources.length(), 1)
  assert_true(sources.get(id) is Some(_))
  assert_eq(sources.require(id).name(), "mapped")
  try sources.add(source) catch {
    DuplicateSource(actual) => assert_eq(actual, id)
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected duplicate source")
  }
  let missing = @source.SourceId::new(10)
  try sources.require(missing) catch {
    MissingSource(actual) => assert_eq(actual, missing)
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing source")
  }
}

///|
test "invalid line, offset, and slice boundaries remain typed" {
  let id = @source.SourceId::new(11)
  let source = @source.Source::from_text(id, "bounds", "中")
  try source.line_text(2) catch {
    InvalidLine(line=2, line_count=1) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid line")
  }
  try source.locate(-1) catch {
    OffsetOutOfBounds(offset=-1, length=3) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid offset")
  }
  try source.slice_text(@source.Span::new(id, 0, 2)) catch {
    InvalidUtf8Boundary(offset=2) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid slice boundary")
  }
}

///|
test "boundary checks cover every UTF-8 width and requested scale" {
  let id = @source.SourceId::new(12)
  let units = ["a", "é", "中", "🙂"]
  let mut text = ""
  for size in [10, 100, 1000, 5000] {
    text = ""
    for index in 0..<size {
      text = text + units[index % units.length()]
    }
    let source = @source.Source::from_text(id, "scaled", text)
    let bytes = source.bytes().to_owned()
    let mut offset = 0
    while offset < bytes.length() {
      let next = bytes[offset]
      source.locate(offset) |> ignore
      if next < 0x80 {
        offset += 1
      } else if next < 0xE0 {
        offset += 2
      } else if next < 0xF0 {
        offset += 3
      } else {
        offset += 4
      }
    }
    assert_eq(source.length(), bytes.length())
    assert_eq(source.locate(source.length()).byte_column(), source.length())
  }
  let no_newline = @source.Source::from_text(
    @source.SourceId::new(13),
    "no-newline",
    "tail",
  )
  let eof = no_newline.locate_terminal_eof()
  assert_eq(eof.line(), 1)
  assert_eq(eof.byte_column(), 4)
  let empty = @source.Source::from_text(@source.SourceId::new(14), "empty", "")
  let empty_eof = empty.locate_terminal_eof()
  assert_eq(empty_eof.line(), 1)
  assert_eq(empty_eof.byte_column(), 0)
  let first = @source.Span::new(@source.SourceId::new(15), 0, 1)
  let other = @source.Span::new(@source.SourceId::new(16), 0, 1)
  try first.cover(other) catch {
    WrongSource(..) => ()
    error => fail("unexpected cover error: \{Repr(error)}")
  } noraise {
    _ => fail("expected wrong source error")
  }
}
