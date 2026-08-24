///|
test "Unix paths clean without escaping an absolute root" {
  let cases = [
    ("", "."),
    (".", "."),
    ("/", "/"),
    ("/a//b/../c/.", "/a/c"),
    ("/../../a", "/a"),
    ("a/../../b", "../b"),
    ("./a/中", "a/中"),
  ]
  for item in cases {
    let (input, expected) = item
    let path = @path.PathValue::new(input, Unix)
    assert_eq(path.as_string(), expected)
    assert_eq(path.clean(), path)
  }
  assert_true(@path.PathValue::new("/a", Unix).is_absolute())
  assert_false(@path.PathValue::new("a", Unix).is_absolute())
}

///|
test "Windows paths clean drives, roots, and UNC shares on every host" {
  let cases = [
    ("C:/work//src/../justfile", "C:\\work\\justfile", true),
    ("C:\\..\\x", "C:\\x", true),
    ("C:foo\\..\\bar", "C:bar", false),
    ("..\\a", "..\\a", false),
    ("\\logs\\..\\out", "\\out", true),
    ("\\\\server\\share\\a\\..\\b", "\\\\server\\share\\b", true),
  ]
  for item in cases {
    let (input, expected, absolute) = item
    let path = @path.PathValue::new(input, Windows)
    assert_eq(path.as_string(), expected)
    assert_eq(path.is_absolute(), absolute)
  }
}

///|
test "join applies the selected flavor instead of the host flavor" {
  let unix = @path.PathValue::new("/workspace/project", Unix).join(
    @path.PathValue::new("../shared", Unix),
  )
  assert_eq(unix.as_string(), "/workspace/shared")
  let windows = @path.PathValue::new("C:\\workspace\\project", Windows).join(
    @path.PathValue::new("..\\shared", Windows),
  )
  assert_eq(windows.as_string(), "C:\\workspace\\shared")
  let rooted = @path.PathValue::new("C:\\workspace", Windows).join(
    @path.PathValue::new("\\logs", Windows),
  )
  assert_eq(rooted.as_string(), "C:\\logs")
  let unc = @path.PathValue::new("\\\\server\\share\\work", Windows).join(
    @path.PathValue::new("\\logs", Windows),
  )
  assert_eq(unc.as_string(), "\\\\server\\share\\logs")
}

///|
test "parent, file name, extension, and extension removal are lexical" {
  let unix = @path.PathValue::new("/a/archive.tar.gz", Unix)
  assert_eq(unix.parent().map(PathValue::as_string), Some("/a"))
  assert_eq(unix.file_name(), Some("archive.tar.gz"))
  assert_eq(unix.extension(), Some("gz"))
  assert_eq(unix.without_extension().as_string(), "/a/archive.tar")
  assert_eq(@path.PathValue::new(".env", Unix).extension(), None)
  assert_eq(@path.PathValue::new(".env.local", Unix).extension(), Some("local"))
  assert_eq(@path.PathValue::new("name.", Unix).extension(), Some(""))
  assert_eq(
    @path.PathValue::new("中.配置", Unix).extension(),
    Some("配置"),
  )
  assert_eq(@path.PathValue::new("/", Unix).parent(), None)
  assert_eq(
    @path.PathValue::new("C:\\file", Windows).parent().map(PathValue::as_string),
    Some("C:\\"),
  )
}

///|
test "path errors reject invalid composition and NUL" {
  let unix = @path.PathValue::new("a", Unix)
  let windows = @path.PathValue::new("a", Windows)
  try unix.join(windows) catch {
    FlavorMismatch(expected=Unix, actual=Windows) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected flavor mismatch")
  }
  try @path.PathValue::new("bad\u{0000}path", Unix) catch {
    NulByte => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected NUL rejection")
  }
}
