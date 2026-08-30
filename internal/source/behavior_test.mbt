///|
test "source tracks utf8 positions and line spans" {
  let source = Source::from_text(SourceId::new(703), "fixture", "a\n猫\n")
  assert_eq(source.line_count(), 3)
  assert_eq(source.line_text(2), "猫")
  let position = source.locate(2)
  assert_eq(position.line(), 2)
  assert_eq(position.byte_column(), 0)
  assert_eq(position.scalar_column(), 0)
}

///|
test "source rejects invalid utf8 bytes" {
  try Source::from_bytes(SourceId::new(704), "fixture", b"\xff") catch {
    InvalidUtf8(..) => ()
    error => fail("unexpected source error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid utf8")
  }
}
