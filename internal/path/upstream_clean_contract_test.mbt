///|
fn assert_clean_contract(input : String, expected : String) -> Unit raise {
  let path = PathValue::new(input, Unix)
  assert_eq(path.clean().as_string(), expected)
}

///|
test "contract JUST-1.57.0-0249 clean::tests::current_dir_after_root_is_removed" {
  assert_clean_contract("/.", "/")
}

///|
test "contract JUST-1.57.0-0250 clean::tests::empty_path_maps_to_current_dir" {
  assert_clean_contract("", ".")
}

///|
test "contract JUST-1.57.0-0251 clean::tests::intermediate_current_dir_is_removed" {
  assert_clean_contract("foo/./bar", "foo/bar")
}

///|
test "contract JUST-1.57.0-0252 clean::tests::intermediate_parent_dir_is_removed" {
  assert_clean_contract("/foo/../bar", "/bar")
}

///|
test "contract JUST-1.57.0-0253 clean::tests::leading_current_dir_is_removed" {
  assert_clean_contract("./foo", "foo")
}

///|
test "contract JUST-1.57.0-0254 clean::tests::leading_parent_dir_is_preserved" {
  assert_clean_contract("..", "..")
}

///|
test "contract JUST-1.57.0-0255 clean::tests::multiple_current_dirs_are_collapsed" {
  assert_clean_contract("././.", ".")
}

///|
test "contract JUST-1.57.0-0256 clean::tests::multiple_current_dirs_are_removed" {
  assert_clean_contract("././.", ".")
}

///|
test "contract JUST-1.57.0-0257 clean::tests::multiple_parent_dirs_are_preserved" {
  assert_clean_contract("../../..", "../../..")
}

///|
test "contract JUST-1.57.0-0258 clean::tests::multiple_slashes_are_removed" {
  assert_clean_contract("//foo//bar//", "/foo/bar")
}

///|
test "contract JUST-1.57.0-0259 clean::tests::normal_after_root_is_preserved" {
  assert_clean_contract("/foo", "/foo")
}

///|
test "contract JUST-1.57.0-0260 clean::tests::normal_is_preserved" {
  assert_clean_contract("foo", "foo")
}

///|
test "contract JUST-1.57.0-0261 clean::tests::parent_dir_after_normal_is_current" {
  assert_clean_contract("foo/..", ".")
}

///|
test "contract JUST-1.57.0-0262 clean::tests::parent_dir_after_root_is_removed" {
  assert_clean_contract("/..", "/")
}

///|
test "contract JUST-1.57.0-0263 clean::tests::single_current_dir_is_preserved" {
  assert_clean_contract(".", ".")
}

///|
test "contract JUST-1.57.0-0264 clean::tests::trailing_current_dir_is_removed" {
  assert_clean_contract("foo/.", "foo")
}

///|
test "contract JUST-1.57.0-0265 clean::tests::trailing_parent_dir_after_current_dir_is_preserved" {
  assert_clean_contract("./..", "..")
}

///|
test "contract JUST-1.57.0-0266 clean::tests::trailing_parent_dir_pops_normal" {
  assert_clean_contract("/foo/bar/..", "/foo")
}

///|
test "contract JUST-1.57.0-0267 clean::tests::trailing_parent_dir_pops_normal_before_current" {
  assert_clean_contract("/foo/bar/./..", "/foo")
}

///|
test "contract JUST-1.57.0-0268 clean::tests::trailing_slash_is_removed" {
  assert_clean_contract("foo/", "foo")
}
