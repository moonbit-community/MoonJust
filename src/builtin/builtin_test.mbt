///|
test "pure builtins cover string, path, regex and semver contracts" {
  assert_eq(call("uppercase", [String("Moon")]), String("MOON"))
  assert_eq(call("trim", [String("  x  ")]), String("x"))
  assert_eq(
    call("replace", [String("hello"), String("ell"), String("i")]),
    String("hio"),
  )
  assert_eq(
    call("regex_matches", [String("hello"), String("h[ae]llo")]),
    Bool(true),
  )
  try call("regex_matches", [String("hello"), String("(")]) catch {
    InvalidPattern(_) => ()
    _ => fail("expected invalid regexp error")
  } noraise {
    _ => fail("expected invalid regexp error")
  }
  assert_eq(
    call("semver_matches", [String("1.5.0"), String(">=1.4")]),
    Bool(true),
  )
  assert_eq(call("path_join", [String("a"), String("b")]), String("a/b"))
  assert_eq(
    call("sha256", [String("abc")]),
    String("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
  )
  assert_eq(
    call("blake3", [String("")]),
    String("af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"),
  )
  assert_eq(
    call("blake3", [String("abc")]),
    String("6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85"),
  )
  assert_eq(
    call("blake3", [String("a".repeat(1025))]),
    String("c59d2e12583df14d951e757a42f1734d355c8c5b1db6b6a33ab2bfabeed40c7d"),
  )
}
