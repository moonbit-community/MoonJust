///|
test "coverage merge rejects invalid schema" {
  let errors : Array[String] = []
  let report = parse_report("{\"schema_version\":2}", "invalid.json", errors)
  assert_true(report is None)
  assert_true(errors.any(fn(error) { error.contains("schema must be 5") }))
}

///|
test "coverage merge requires row execution fields" {
  let errors : Array[String] = []
  let report = parse_report(
    "{\"schema_version\":5,\"upstream\":\"just 1.59.0\",\"runner_os\":\"linux\",\"target\":\"wasm\",\"upstream_total\":1,\"failures\":0,\"differential_known_difference\":0,\"product_identity_difference\":2,\"rows\":[{\"upstream_id\":\"x\"}]}",
    "invalid-row.json", errors,
  )
  assert_true(report is Some(_))
  assert_true(
    errors.any(fn(error) { error.contains("missing a required field") }),
  )
}

///|
test "merge requires executed document and smoke checks and excluded repository checks" {
  assert_eq(
    expected_execution("host-limited", "linux", "linux"),
    "deferred-host",
  )
  assert_eq(
    expected_execution("host-limited", "linux", "windows"),
    "deferred-platform",
  )
  assert_eq(expected_execution("document-oracle", "all", "linux"), "executed")
  assert_eq(expected_execution("local-smoke", "all", "windows"), "executed")
  assert_eq(expected_execution("repository-only", "all", "macos"), "excluded")
  assert_eq(
    expected_execution("differential", "windows", "linux"),
    "deferred-platform",
  )
  assert_eq(expected_execution("differential", "unix", "macos"), "executed")
}

///|
test "a host limitation requires the reviewed upstream identity, platform and reason" {
  let id = "non_unicode::non_unicode_invocation_directory_is_an_error"
  let (platform, reason) = @testkit.deferred_host_behavior(id).unwrap()
  fn row(id : String, required : String, scope : String) -> Json {
    {
      "upstream_id": id,
      "status": "host-limited",
      "evidence_kind": "host-limited",
      "execution_state": "deferred-host",
      "required_platform": required,
      "local_test": "",
      "evidence_scope": scope,
      "fixture": "tests/non_unicode.rs:4",
      "upstream_source_anchor": "tests/non_unicode.rs:4",
    }
  }
  let errors = []
  ignore(parse_row(row(id, platform, reason), errors, "local.json"))
  assert_true(errors.is_empty())
  for
    invalid in [
      row("unknown", platform, reason),
      row(id, "macos", reason),
      row(id, platform, ""),
    ] {
    let errors = []
    ignore(parse_row(invalid, errors, "local.json"))
    assert_true(
      errors.any(message => {
        message.has_suffix(": invalid evidence kind or status")
      }),
    )
  }
}

///|
test "merge rejects an exact status attached to local evidence" {
  let row : Json = {
    "upstream_id": "x",
    "status": "differential-exact",
    "evidence_kind": "local-smoke",
    "execution_state": "executed",
    "required_platform": "all",
    "local_test": "x",
    "evidence_scope": "parser checks two fields",
    "fixture": "example.mbt:2",
    "upstream_source_anchor": "src/parser.rs:2",
  }
  let errors = []
  ignore(parse_row(row, errors, "local.json"))
  assert_true(errors.contains("x: invalid evidence kind or status"))
}
