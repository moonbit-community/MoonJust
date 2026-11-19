///|
test "quote escapes every single quote" {
  for
    (value, expected) in [
      ("", "''"),
      ("abc", "'abc'"),
      ("''", "''\\'''\\'''"),
      ("a'b'c", "'a'\\''b'\\''c'"),
    ] {
    assert_eq(quote(value), expected)
  }
}

///|
test "builtin aliases follow just and regex comparison keeps its own contract" {
  for name in ["stem", "path_join", "regex_matches"] {
    assert_true(find(name) is None)
  }
  assert_true(find("justfile_dir") is Some(_))
  assert_true(try! regex_matches("abc", "^a"))
  assert_false(try! regex_matches("abc", "^b"))
}

///|
test "replace_regex resumes with left context and advances on Unicode boundaries" {
  for
    (value, pattern, replacement, expected) in [
      ("abc", "^", "X", "Xabc"),
      ("a", "a*", "X", "X"),
      ("aba", "a*", "X", "XbX"),
      ("a😀", "", "X", "XaX😀X"),
      ("aa aa", "\\b", "|", "|aa| |aa|"),
      ("a\nb", "(?m:^)", "|", "|a\n|b"),
      ("abba", "(?<x>b)|a", "[$0:$1:$x]", "[a::][b:b:b][b:b:b][a::]"),
    ] {
    let actual = call("replace_regex", [
      String(value),
      String(pattern),
      String(replacement),
    ]) catch {
      error => fail(error.message())
    }
    assert_eq(actual.to_string(), expected)
  }
}

///|
test "semver handles full-width core components and arbitrary numeric identifiers" {
  assert_false(try! semver_matches("4294967296.0.0", "=0.0.0"))
  assert_true(try! semver_matches("18446744073709551615.0.0", ">4294967296"))
  assert_true(
    try! semver_matches("0.1.18446744073709551615", "=0.1.18446744073709551615"),
  )
  assert_true(
    try! semver_matches(
      "1.0.0-100000000000000000000", ">1.0.0-99999999999999999999",
    ),
  )
  assert_true(try! semver_matches("1.0.0-01a", "=1.0.0-01a"))
  for
    (version, reason) in [
      (
        "18446744073709551616.0.0", "value of major version number exceeds u64::MAX",
      ),
      ("1.0.0-01", "invalid leading zero in pre-release identifier"),
    ] {
    try semver_matches(version, "*") catch {
      Failure(message~) =>
        assert_eq(message, "invalid semver version: " + reason)
      error => fail(error.message())
    } noraise {
      _ => fail("expected invalid version")
    }
  }
}
