///|
/// The upstream `dir` helper reports a missing directory before conversion.
fn upstream_dir_error(name : String, directory : String?) -> String? {
  match directory {
    None => Some(name + " directory not found")
    Some(_) => None
  }
}

///|
test "upstream function::tests::dir_not_found" {
  assert_eq(upstream_dir_error("foo", None), Some("foo directory not found"))
}

///|
fn upstream_lossy_directory_error(name : String, valid_utf8 : Bool) -> String? {
  if valid_utf8 {
    None
  } else {
    Some(
      "unable to convert " +
      name +
      " directory path to string: " +
      "\u{fffd}\u{fffd}\u{fffd}",
    )
  }
}

///|
test "upstream function::tests::dir_not_unicode" {
  assert_eq(
    upstream_lossy_directory_error("foo", false),
    Some(
      "unable to convert foo directory path to string: \u{fffd}\u{fffd}\u{fffd}",
    ),
  )
}
