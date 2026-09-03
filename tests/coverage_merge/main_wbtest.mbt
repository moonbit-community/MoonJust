///|
test "coverage merge rejects invalid schema" {
  let errors : Array[String] = []
  let report = parse_report("{\"schema_version\":2}", "invalid.json", errors)
  assert_true(report is None)
  assert_true(errors.any(fn(error) { error.contains("schema must be 3") }))
}

///|
test "coverage merge requires row execution fields" {
  let errors : Array[String] = []
  let report = parse_report(
    "{\"schema_version\":3,\"runner_os\":\"linux\",\"target\":\"native\",\"upstream_total\":1,\"failures\":0,\"differential_known_difference\":0,\"product_identity_difference\":2,\"rows\":[{\"upstream_id\":\"x\"}]}",
    "invalid-row.json", errors,
  )
  assert_true(report is Some(_))
  assert_true(
    errors.any(fn(error) { error.contains("missing a required field") }),
  )
}
