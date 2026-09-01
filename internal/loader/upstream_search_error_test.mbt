///|
test "upstream search_error::tests::multiple_candidates_formatting" {
  let error = LoaderError::AmbiguousJustfile(
    directory=try! @path.PathValue::new("/foo", Unix),
    found=["JUSTFILE", "justfile"],
  )
  assert_eq(
    error.message(),
    "multiple candidate justfiles found in `/foo`: `JUSTFILE` and `justfile`",
  )
}
