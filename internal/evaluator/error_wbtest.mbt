///|
test "canonicalize errors use the official Windows not-found detail" {
  let path = @path.PathValue::new("C:\\work\\foo", Windows)
  assert_eq(
    canonicalize_host_error_detail(@host.HostError::NotFound(path), path),
    "The system cannot find the file specified. (os error 2)",
  )
  assert_eq(
    canonicalize_host_error_detail(
      @host.HostError::InvalidInput(
        "The system cannot find the file specified. (os error 2): C:\\work\\foo",
      ),
      path,
    ),
    "The system cannot find the file specified. (os error 2)",
  )
}
