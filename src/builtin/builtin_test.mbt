///|
test "pure builtins cover string, path, regex and semver contracts" {
  assert_eq(call("uppercase", [String("Moon")]), String("MOON"))
  assert_eq(call("trim", [String("  x  ")]), String("x"))
  assert_eq(
    call("replace", [String("hello"), String("ell"), String("i")]),
    String("hio"),
  )
  assert_eq(
    call("replace_regex", [String("hello"), String("h."), String("y")]),
    String("yllo"),
  )
  assert_eq(
    call("replace_regex", [
      String("a1 b22"),
      String("([a-z])(\\d+)"),
      String("$2-$1"),
    ]),
    String("1-a 22-b"),
  )
  assert_eq(
    call("replace_regex", [
      String("ab ab"),
      String("(?<word>ab)"),
      String("${word}!"),
    ]),
    String("ab! ab!"),
  )
  assert_eq(
    call("replace_regex", [String("aa"), String("a"), String("$$")]),
    String("$$"),
  )
  assert_eq(
    call("replace_regex", [String("ab"), String(""), String("-")]),
    String("-a-b-"),
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
  try call("regex_matches", [String("hello"), String("(h)\\1")]) catch {
    InvalidPattern(_) => ()
    _ => fail("expected unsupported regexp error")
  } noraise {
    _ => fail("expected unsupported regexp error")
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

///|
test "builtin registry freezes canonical inventory and purity metadata" {
  assert_eq(@builtin.names().length(), 83)
  assert_eq(@builtin.registry().length(), 83)
  let unique : Set[String] = Set([])
  for spec in @builtin.registry() {
    unique.add(spec.name())
    assert_true(spec.min_arguments() >= 0)
    assert_true(spec.accepts_arity(spec.min_arguments()))
    assert_eq(spec.targets(), [Native, Wasm1])
    assert_true(spec.evidence().contains(spec.name()))
  }
  assert_eq(unique.length(), 83)
  assert_true(
    @builtin.registry()
    .iter()
    .any(fn(spec) {
      spec.name() == "shell" &&
      spec.purity() is Effect &&
      spec.min_arguments() == 1 &&
      spec.max_arguments() is None &&
      spec.capabilities() == [Context, Process]
    }),
  )
  assert_true(
    @builtin.registry()
    .iter()
    .any(fn(spec) { spec.name() == "join" && spec.purity() is Pure }),
  )
  assert_eq(@builtin.canonical_name("source_dir"), "source_directory")
  assert_eq(
    @builtin.canonical_name("invocation_dir_native"),
    "invocation_directory_native",
  )
  assert_eq(@builtin.find("canonicalize").unwrap().capabilities(), [
    Context,
    FsRead,
  ])
  assert_eq(@builtin.find("which").unwrap().capabilities(), [
    Context,
    FsRead,
    Environment,
    Platform,
  ])
  assert_true(@builtin.is_effectful("canonicalize"))
  assert_true(!@builtin.find("replace_regex").unwrap().accepts_arity(2))
}

///|
fn chunk_bytes(bytes : Bytes, sizes : ArrayView[Int]) -> Array[Bytes] {
  let chunks : Array[Bytes] = []
  let mut offset = 0
  let mut size_index = 0
  while offset < bytes.length() {
    let requested = sizes[size_index % sizes.length()]
    let end = Int::min(offset + requested, bytes.length())
    chunks.push(bytes[offset:end].to_owned())
    offset = end
    size_index += 1
  }
  if chunks.is_empty() {
    chunks.push(b"")
  }
  chunks
}

///|
test "incremental hashes are independent of adversarial chunk boundaries" {
  for length in [0, 1, 63, 64, 65, 1023, 1024, 1025, 2048, 4097] {
    let values : Array[Byte] = []
    for index in 0..<length {
      values.push(((index * 37 + 11) & 255).to_byte())
    }
    let bytes = Bytes::from_array(values)
    for sizes in [[1], [3, 5, 7, 11], [63, 64, 65], [1023, 1, 1024]] {
      let chunks = chunk_bytes(bytes, sizes[:])
      assert_eq(@builtin.sha256_chunks(chunks[:]), @builtin.sha256_bytes(bytes))
      assert_eq(@builtin.blake3_chunks(chunks[:]), @builtin.blake3_bytes(bytes))
    }
  }
}

///|
test "incremental hashes handle a large input without whole-input reassembly" {
  let values : Array[Byte] = []
  for index in 0..<(1024 * 1024 + 17) {
    values.push(((index * 17 + 29) & 255).to_byte())
  }
  let bytes = Bytes::from_array(values)
  let chunks = chunk_bytes(bytes, [17, 4096, 65536])
  assert_eq(@builtin.sha256_chunks(chunks[:]), @builtin.sha256_bytes(bytes))
  assert_eq(@builtin.blake3_chunks(chunks[:]), @builtin.blake3_bytes(bytes))
}

///|
test "semver handles prerelease, wildcard and range operators" {
  assert_eq(
    call("semver_matches", [String("1.2.3-alpha"), String("<1.2.3")]),
    Bool(false),
  )
  assert_eq(
    call("semver_matches", [
      String("1.2.3-alpha.2"),
      String(">=1.2.3-alpha.1, <1.2.3"),
    ]),
    Bool(true),
  )
  assert_eq(
    call("semver_matches", [String("1.9.0"), String("^1.2.3")]),
    Bool(true),
  )
  assert_eq(
    call("semver_matches", [String("2.0.0"), String("^1.2.3")]),
    Bool(false),
  )
  assert_eq(
    call("semver_matches", [String("1.2.9"), String("~1.2.3")]),
    Bool(true),
  )
  assert_eq(
    call("semver_matches", [String("1.3.0"), String("1.2.x")]),
    Bool(false),
  )
  assert_eq(
    call("semver_matches", [String("1.8.0"), String(">=1.0.0, <2.0.0")]),
    Bool(true),
  )
  assert_eq(
    call("semver_matches", [String("1.2.3+build.5"), String("=1.2.3")]),
    Bool(true),
  )
  assert_eq(
    call("semver_matches", [String("0.0.5"), String("^0.0")]),
    Bool(true),
  )
  assert_eq(
    call("semver_matches", [String("1.9.0"), String("1.2.3")]),
    Bool(true),
  )
  assert_eq(
    call("semver_matches", [String("1.3.0"), String("1.2")]),
    Bool(true),
  )
  assert_eq(
    call("semver_matches", [String("1.2.3"), String("=1.2")]),
    Bool(true),
  )
  assert_eq(
    call("semver_matches", [String("1.2.3"), String("=1.2.*")]),
    Bool(true),
  )
  assert_eq(
    call("semver_matches", [String("1.2.3"), String(">1.2")]),
    Bool(false),
  )
  assert_eq(
    call("semver_matches", [String("1.2.3"), String("<=1.2")]),
    Bool(true),
  )
  assert_eq(
    call("semver_matches", [String("1.2.3"), String(">= 1.2, < 2")]),
    Bool(true),
  )
  for invalid in ["1.*.2", "=*"] {
    try call("semver_matches", [String("1.2.3"), String(invalid)]) catch {
      InvalidRequirement(_) => ()
      _ => fail("unexpected wildcard requirement error")
    } noraise {
      _ => fail("expected invalid wildcard requirement")
    }
  }
  try
    call("semver_matches", [String("1.8.0"), String(">=1.0.0 <2.0.0")])
  catch {
    InvalidRequirement(_) => ()
    _ => fail("expected Rust-compatible comma requirement")
  } noraise {
    _ => fail("expected invalid requirement")
  }
}

///|
test "canonical string and list builtins are deterministic" {
  assert_eq(
    call("append", [String("b"), List([String("a"), String("c")])]),
    List([String("ab"), String("cb")]),
  )
  assert_eq(
    call("prepend", [String("a"), List([String("b")])]),
    List([String("ab")]),
  )
  assert_eq(
    call("split", [String("a,b"), String(",")]),
    List([String("a"), String("b")]),
  )
  assert_eq(call("kebabcase", [String("Hello_world")]), String("hello-world"))
  assert_eq(
    call("trim_start_match", [String("prefix-value"), String("prefix-")]),
    String("value"),
  )
  assert_eq(call("trim_end_matches", [String("aaaa"), String("a")]), String(""))
  assert_eq(
    call("split", [String("a  b\tc")]),
    List([String("a"), String("b"), String("c")]),
  )
  assert_eq(
    call("join_list", [List([String("a"), String("b")])]),
    String("a b"),
  )
  assert_eq(call("kebabcase", [String("HelloWorld")]), String("hello-world"))
}
