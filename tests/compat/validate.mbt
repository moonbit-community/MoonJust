///|
async fn validate_inventory(
  manifest : CompatibilityManifest,
  cases_root : String,
  upstream_names : Set[String],
  spec_index : Map[String, SpecCase],
  spec_text : String,
  failures : Array[String],
) -> Unit {
  let metadata = manifest.cases
  let fixture_cache : Map[String, Array[StringView]] = Map([])
  if manifest.schema_version != 3 {
    failures.push("compatibility manifest schema_version must be 3")
  }
  if manifest.upstream != "just 1.59.0" {
    failures.push("compatibility manifest upstream must be `just 1.59.0`")
  }
  let manifest_upstream : Set[String] = Set([])
  for error in spec_index_shape_errors(spec_text) {
    failures.push(error)
  }
  for name, details in metadata {
    let case_dir = join(cases_root, name)
    for error in fixture_structure_errors(name, case_dir) {
      failures.push(error)
    }
    if details.status != "match" && details.status != "expected-difference" {
      failures.push(name + ": invalid manifest status " + details.status)
    }
    for required in ["status", "stdout", "stderr"] {
      if !details.compare.contains(required) {
        failures.push(name + ": compare omits required field " + required)
      }
    }
    for field in details.compare {
      if !["status", "stdout", "stderr", "merged", "tree", "live"].contains(
          field,
        ) {
        failures.push(name + ": compare contains unknown field " + field)
      }
    }
    for rule in details.normalizations {
      if ![
          "datetime", "duration", "timestamp", "choose", "uuid", "parallel-order",
          "program-path", "temp-path", "canonical-path", "module-path",
        ].contains(rule) {
        failures.push(name + ": unknown output normalization " + rule)
      }
    }
    if details.status == "expected-difference" {
      let identity = ["01-version", "02-help"].contains(name) &&
        details.upstream_tests.is_empty() &&
        details.allowed_difference == Some("product-identity") &&
        details.candidate_stdout_sha256 is Some(_)
      if !identity && refusal_digest(name, details) is None {
        failures.push(name + ": difference is not on the reviewed allowlist")
      }
    }
    for upstream_test in details.upstream_tests {
      if manifest_upstream.contains(upstream_test) {
        failures.push(
          "duplicate differential upstream identity: " + upstream_test,
        )
      } else {
        manifest_upstream.add(upstream_test)
      }
      if !upstream_names.contains(upstream_test) {
        failures.push(
          name +
          ": upstream anchor is absent from pinned just test list: " +
          upstream_test,
        )
      }
    }
    if details.upstream_tests.length() != details.upstream_anchors.length() {
      failures.push(name + ": upstream test and anchor counts differ")
    } else {
      for index, upstream_test in details.upstream_tests {
        match
          validate_upstream_anchor(
            upstream_test,
            details.upstream_anchors[index],
          ) {
          Some(error) => failures.push(error)
          None => ()
        }
      }
    }
  }
  for upstream_test, spec in spec_index {
    let fixture_file = spec.fixture
      .split(":")
      .collect()
      .get(0)
      .unwrap_or("")
      .to_owned()
    if !upstream_names.contains(upstream_test) {
      failures.push(
        upstream_test +
        ": spec index entry is absent from pinned just test list",
      )
    }
    if fixture_file.is_empty() || !@fs.exists(fixture_file) {
      failures.push(
        upstream_test + ": spec fixture is missing: " + spec.fixture,
      )
    }
    if !fixture_file.is_empty() &&
      @fs.exists(fixture_file) &&
      !audited_fixture(upstream_test, spec, fixture_cache) {
      failures.push(
        upstream_test +
        ": upstream fixture must contain source-backed input and expected sections",
      )
    }
    if spec.anchor.is_empty() {
      failures.push(
        upstream_test + ": spec is missing an upstream source anchor",
      )
    }
    match validate_upstream_anchor(upstream_test, spec.anchor) {
      Some(error) => failures.push(error)
      None => ()
    }
    match validate_spec_anchor(upstream_test, spec) {
      Some(error) => failures.push(error)
      None => ()
    }
  }
  for name, _ in metadata {
    if !@fs.exists(join(cases_root, name)) {
      failures.push(name + ": manifest case directory is missing")
    }
  }
}
