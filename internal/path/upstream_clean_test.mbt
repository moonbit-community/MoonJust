///|
fn assert_clean_path(
  raw : String,
  expected : String,
  flavor : @path.PathFlavor,
) -> Unit raise {
  let value = @path.PathValue::new(raw, flavor) catch {
    _ => fail("path normalization unexpectedly rejected input")
  }
  assert_eq(value.as_string(), expected)
}

///|
test "clean empty_path_maps_to_current_dir" {
  assert_clean_path("", ".", Unix)
}

///|
test "clean single_current_dir_is_preserved" {
  assert_clean_path(".", ".", Unix)
}

///|
test "clean multiple_current_dirs_are_collapsed" {
  assert_clean_path("././.", ".", Unix)
}

///|
test "clean leading_parent_dir_is_preserved" {
  assert_clean_path("..", "..", Unix)
}

///|
test "clean multiple_parent_dirs_are_preserved" {
  assert_clean_path("../../..", "../../..", Unix)
}

///|
test "clean trailing_slash_is_removed" {
  assert_clean_path("foo/", "foo", Unix)
}

///|
test "clean leading_current_dir_is_removed" {
  assert_clean_path("./foo", "foo", Unix)
}

///|
test "clean trailing_parent_dir_after_current_dir_is_preserved" {
  assert_clean_path("./..", "..", Unix)
}

///|
test "clean trailing_current_dir_is_removed" {
  assert_clean_path("foo/.", "foo", Unix)
}

///|
test "clean intermediate_current_dir_is_removed" {
  assert_clean_path("foo/./bar", "foo/bar", Unix)
}

///|
test "clean multiple_current_dirs_are_removed" {
  assert_clean_path("././.", ".", Unix)
}

///|
test "clean parent_dir_after_root_is_removed" {
  assert_clean_path("/..", "/", Unix)
}

///|
test "clean current_dir_after_root_is_removed" {
  assert_clean_path("/.", "/", Unix)
}

///|
test "clean multiple_slashes_are_removed" {
  assert_clean_path("//foo//bar//", "/foo/bar", Unix)
}

///|
test "clean normal_after_root_is_preserved" {
  assert_clean_path("/foo", "/foo", Unix)
}

///|
test "clean intermediate_parent_dir_is_removed" {
  assert_clean_path("/foo/../bar", "/bar", Unix)
}

///|
test "clean trailing_parent_dir_pops_normal" {
  assert_clean_path("/foo/bar/..", "/foo", Unix)
}

///|
test "clean trailing_parent_dir_pops_normal_before_current" {
  assert_clean_path("/foo/bar/./..", "/foo", Unix)
}

///|
test "clean normal_is_preserved" {
  assert_clean_path("foo", "foo", Unix)
}

///|
test "clean parent_dir_after_normal_is_current" {
  assert_clean_path("foo/..", ".", Unix)
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
    check_search_clean(expected, Unix)
    check_search_clean(expected, Windows)
  }
  check_search_clean(("//foo", "bar//baz", "//foo\\bar\\baz"), Windows)
}

///|
test "clean parent_dir_after_disk_is_removed" {
  assert_clean_path("C:\\..", "C:\\", Windows)
}

///|
fn check_search_clean(
  paths : (String, String, String),
  flavor : @path.PathFlavor,
) -> Unit raise {
  let base = @path.PathValue::new(paths.0, flavor)
  let child = @path.PathValue::new(paths.1, flavor)
  let expected = paths.2.replace_all(
    old="/",
    new=flavor.separator().to_string(),
  )
  assert_eq(base.join(child).clean().as_string(), expected)
  assert_eq(base.join_text(paths.1).as_string(), expected)
}

///|
test "a share introduced by a relative spelling is protected during the join" {
  for spelling in ["//server", "//?/UNC/server"] {
    let server = @path.PathValue::new(spelling, Windows)
    let prefix = spelling.replace_all(old="/", new="\\")
    assert_eq(server.as_string(), prefix)
    assert_eq(
      server.join_text("./share/../../x").as_string(),
      prefix + "\\share\\x",
    )
    assert_eq(
      server.join_text("//other/share/x").as_string(),
      "\\\\other\\share\\x",
    )
    assert_true(server.parent() is None)
  }
}

///|
test "UNC share roots bound parent traversal and rooted children" {
  for
    prefix in ["//server/share", "//?/UNC/server/share", "//./UNC/server/share"] {
    let root = @path.PathValue::new(prefix, Windows)
    let root_text = prefix.replace_all(old="/", new="\\")
    assert_eq(root.as_string(), root_text)
    assert_true(root.parent() is None)
    assert_true(root.file_name() is None)
    let file = @path.PathValue::new(prefix + "/a/b", Windows)
    assert_eq(file.parent().unwrap().parent(), Some(root))
    assert_eq(
      file.join(@path.PathValue::new("../../../../x", Windows)).as_string(),
      root_text + "\\x",
    )
    assert_eq(
      file.join(@path.PathValue::new("/x", Windows)).as_string(),
      root_text + "\\x",
    )
    assert_eq(
      @path.PathValue::new(prefix + "/../x", Windows).as_string(),
      root_text + "\\x",
    )
  }
}

///|
test "Windows device and drive prefixes retain their lexical roots" {
  for prefix in ["//./pipe", "//?/C:", "//?/Volume{guid}"] {
    let root = @path.PathValue::new(prefix, Windows)
    assert_eq(root.as_string(), prefix.replace_all(old="/", new="\\"))
    assert_true(root.is_absolute())
    assert_true(root.parent() is None)
    let item = @path.PathValue::new(prefix + "/a/../b", Windows)
    assert_eq(item.parent(), Some(root))
    assert_eq(item.file_name(), Some("b"))
    assert_eq(
      item.join(@path.PathValue::new("/next", Windows)).as_string(),
      root.as_string() + "\\next",
    )
  }
  assert_false(@path.PathValue::new("C:relative", Windows).is_absolute())
  assert_eq(
    @path.PathValue::new("C:/", Windows)
    .join(@path.PathValue::new("file", Windows))
    .as_string(),
    "C:\\file",
  )
}
