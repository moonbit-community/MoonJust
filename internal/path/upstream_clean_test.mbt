///|
fn assert_clean_path(
  raw : String,
  expected : String,
  flavor : PathFlavor,
) -> Unit raise {
  let value = PathValue::new(raw, flavor) catch {
    _ => fail("path normalization unexpectedly rejected input")
  }
  assert_eq(value.as_string(), expected)
}

///|
test "clean empty_path_maps_to_current_dir" {
  assert_clean_path("", ".", PathFlavor::Unix)
}

///|
test "clean single_current_dir_is_preserved" {
  assert_clean_path(".", ".", PathFlavor::Unix)
}

///|
test "clean multiple_current_dirs_are_collapsed" {
  assert_clean_path("././.", ".", PathFlavor::Unix)
}

///|
test "clean leading_parent_dir_is_preserved" {
  assert_clean_path("..", "..", PathFlavor::Unix)
}

///|
test "clean multiple_parent_dirs_are_preserved" {
  assert_clean_path("../../..", "../../..", PathFlavor::Unix)
}

///|
test "clean trailing_slash_is_removed" {
  assert_clean_path("foo/", "foo", PathFlavor::Unix)
}

///|
test "clean leading_current_dir_is_removed" {
  assert_clean_path("./foo", "foo", PathFlavor::Unix)
}

///|
test "clean trailing_parent_dir_after_current_dir_is_preserved" {
  assert_clean_path("./..", "..", PathFlavor::Unix)
}

///|
test "clean trailing_current_dir_is_removed" {
  assert_clean_path("foo/.", "foo", PathFlavor::Unix)
}

///|
test "clean intermediate_current_dir_is_removed" {
  assert_clean_path("foo/./bar", "foo/bar", PathFlavor::Unix)
}

///|
test "clean multiple_current_dirs_are_removed" {
  assert_clean_path("././.", ".", PathFlavor::Unix)
}

///|
test "clean parent_dir_after_root_is_removed" {
  assert_clean_path("/..", "/", PathFlavor::Unix)
}

///|
test "clean current_dir_after_root_is_removed" {
  assert_clean_path("/.", "/", PathFlavor::Unix)
}

///|
test "clean multiple_slashes_are_removed" {
  assert_clean_path("//foo//bar//", "/foo/bar", PathFlavor::Unix)
}

///|
test "clean normal_after_root_is_preserved" {
  assert_clean_path("/foo", "/foo", PathFlavor::Unix)
}

///|
test "clean intermediate_parent_dir_is_removed" {
  assert_clean_path("/foo/../bar", "/bar", PathFlavor::Unix)
}

///|
test "clean trailing_parent_dir_pops_normal" {
  assert_clean_path("/foo/bar/..", "/foo", PathFlavor::Unix)
}

///|
test "clean trailing_parent_dir_pops_normal_before_current" {
  assert_clean_path("/foo/bar/./..", "/foo", PathFlavor::Unix)
}

///|
test "clean normal_is_preserved" {
  assert_clean_path("foo", "foo", PathFlavor::Unix)
}

///|
test "clean parent_dir_after_normal_is_current" {
  assert_clean_path("foo/..", ".", PathFlavor::Unix)
}

///|
test "upstream search::tests::clean" {
  for
    expected in [
      ("/", "foo", "/foo"),
      ("/bar", "/foo", "/foo"),
      ("/", "..", "/"),
      ("/", "/..", "/"),
      ("/..", "", "/"),
      ("/../../../..", "../../../", "/"),
      ("/.", "./", "/"),
      ("/foo/../", "bar", "/bar"),
      ("/foo/bar", "..", "/foo"),
      ("/foo/bar/", "..", "/foo"),
    ] {
    let prefix = try! PathValue::new(expected.0, Unix)
    let suffix = try! PathValue::new(expected.1, Unix)
    assert_eq(try! prefix.join(suffix).clean().as_string(), expected.2)
  }
}
