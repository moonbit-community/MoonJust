///|
fn json_string(value : String) -> String {
  "\"" +
  value.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"") +
  "\""
}

///|
fn excluded_reason(upstream_test : String) -> String? {
  if upstream_test.has_prefix("completions::") {
    Some("completion generation protocol is shell-specific")
  } else if upstream_test.has_prefix("signals::") {
    Some("runtime signal identity and forwarding are OS-specific")
  } else {
    None
  }
}

///|
fn coverage_status(
  upstream_test : String,
  metadata : Map[String, CaseMetadata],
) -> (String, String, String, String) {
  for name, details in metadata {
    if details.upstream_tests.contains(upstream_test) {
      let status = if details.status == "match" {
        "differential-exact"
      } else {
        "differential-known-difference"
      }
      return (status, name, upstream_test, "")
    }
  }
  match excluded_reason(upstream_test) {
    Some(reason) if upstream_test.has_prefix("completions::") =>
      ("excluded-completion", "", "", reason)
    Some(reason) => ("excluded-signal", "", "", reason)
    None => ("unclassified", "", "", "")
  }
}

///|
fn coverage_json(
  upstream_names : Set[String],
  metadata : Map[String, CaseMetadata],
) -> String {
  let rows : Array[String] = []
  let mut exact = 0
  let mut known = 0
  let mut completion = 0
  let mut signal = 0
  let mut unclassified = 0
  for upstream_test in upstream_names {
    let (status, fixture, anchor, reason) = coverage_status(
      upstream_test, metadata,
    )
    match status {
      "differential-exact" => exact += 1
      "differential-known-difference" => known += 1
      "excluded-completion" => completion += 1
      "excluded-signal" => signal += 1
      _ => unclassified += 1
    }
    rows.push(
      "{\"upstream_id\":" +
      json_string(upstream_test) +
      ",\"status\":" +
      json_string(status) +
      ",\"fixture\":" +
      json_string(fixture) +
      ",\"upstream_source_anchor\":" +
      json_string(anchor) +
      ",\"difference_reason\":" +
      json_string(reason) +
      "}",
    )
  }
  "{\"schema_version\":1,\"upstream_total\":" +
  upstream_names.length().to_string() +
  ",\"executed_total\":" +
  (exact + known).to_string() +
  ",\"exact_total\":" +
  exact.to_string() +
  ",\"known_difference_total\":" +
  known.to_string() +
  ",\"excluded_completion_total\":" +
  completion.to_string() +
  ",\"excluded_signal_total\":" +
  signal.to_string() +
  ",\"unclassified_total\":" +
  unclassified.to_string() +
  ",\"rows\":[" +
  rows.join(",") +
  "]}\n"
}
