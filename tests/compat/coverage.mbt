///|
priv struct SpecCase {
  fixture : String
  anchor : String
}

///|
fn parse_spec_index(text : String) -> Map[String, SpecCase] {
  let result : Map[String, SpecCase] = Map([])
  for raw in text.split("\n") {
    let line = raw.trim().to_owned()
    if line.is_empty() || line.has_prefix("#") {
      continue
    }
    let fields = line.split("\t").collect()
    if fields.length() >= 3 {
      result[fields[0].to_owned()] = {
        fixture: fields[1].to_owned(),
        anchor: fields[2].to_owned(),
      }
    }
  }
  result
}

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
  specs : Map[String, SpecCase],
) -> (String, String, String, String) {
  for name, details in metadata {
    if details.upstream_tests.contains(upstream_test) {
      let status = if details.status == "match" {
        "differential-exact"
      } else {
        "differential-known-difference"
      }
      let reason = details.allowed_difference.unwrap_or("")
      return (status, name, upstream_test, reason)
    }
  }
  // Concrete MoonBit assertion files are executable spec evidence. The large
  // Rust source snapshot is audit evidence only and must not inflate coverage.
  if specs.get(upstream_test) is Some(spec) {
    let fixture_path = spec.fixture
      .split(":")
      .collect()
      .get(0)
      .unwrap_or("")
      .to_owned()
    if !fixture_path.has_suffix("upstream-fixtures.txt") {
      return ("moonbit-spec-exact", spec.fixture, spec.anchor, "")
    }
    return ("unclassified", spec.fixture, spec.anchor, "source-snapshot-only")
  }
  match excluded_reason(upstream_test) {
    Some(reason) if upstream_test.has_prefix("completions::") =>
      ("excluded-completion", "", "", reason)
    Some(reason) => ("excluded-signal", "", "", reason)
    None => ("unclassified", "", "", "")
  }
}

///|
/// Validate the generated upstream snapshot format used for migrated cases.
///  A snapshot is deliberately source-backed: it must contain the original
///  test body in both the input and expected sections, so an index row cannot
///  claim coverage with an empty placeholder file.
async fn audited_fixture(
  upstream_test : String,
  fixture_file : String,
  anchor : String,
  cache : Map[String, String],
) -> Bool {
  if !fixture_file.has_suffix("upstream-fixtures.txt") {
    return true
  }
  let text = match cache.get(fixture_file) {
    Some(value) => value
    None => {
      let value = @fs.read_file(fixture_file).text() catch { _ => "" }
      cache[fixture_file] = value
      value
    }
  }
  let marker = "=== " + upstream_test + " ==="
  guard text.find(marker) is Some(start) else { return false }
  let tail = text.view(start_offset=start)
  guard tail.find("=== end ===") is Some(end) else { return false }
  let block = tail[:end].to_owned()
  let has_assertion = block.contains("assert") ||
    block.contains("success()") ||
    block.contains("failure()") ||
    block.contains(".stdout") ||
    block.contains(".stderr") ||
    block.contains(".status(") ||
    block.contains("tree:") ||
    block.contains("values:") ||
    block.contains("text:") ||
    block.contains("case(") ||
    block.contains("want:") ||
    block.contains("args:") ||
    block.contains("subcommand:") ||
    block.contains("verbosity:") ||
    block.contains("search_config:") ||
    block.contains("run(") ||
    block.contains("evaluate(") ||
    block.contains("Version::") ||
    block.contains("Signal::") ||
    block.contains("unwrap()") ||
    block.contains("kind:") ||
    block.contains("offset:") ||
    block.contains("Config {") ||
    block.contains("Module {") ||
    block.contains("Token {")
  block.contains("\nsource: " + anchor + "\n") &&
  block.contains("\ninput:\n") &&
  block.contains("\nexpected:\n") &&
  has_assertion
}

///|
fn coverage_json(
  upstream_names : Set[String],
  metadata : Map[String, CaseMetadata],
  specs : Map[String, SpecCase],
) -> String {
  let rows : Array[String] = []
  let mut exact = 0
  let mut known = 0
  let mut completion = 0
  let mut signal = 0
  let mut unclassified = 0
  for upstream_test in upstream_names {
    let (status, fixture, anchor, reason) = coverage_status(
      upstream_test, metadata, specs,
    )
    let candidate_digest = match status {
      "differential-known-difference" => {
        let mut digest = ""
        for _, details in metadata {
          if details.upstream_tests.contains(upstream_test) {
            digest = details.candidate_stdout_sha256.unwrap_or(
              details.candidate_stderr_sha256.unwrap_or(""),
            )
            break
          }
        }
        digest
      }
      _ => ""
    }
    match status {
      "differential-exact" => exact += 1
      "differential-known-difference" => known += 1
      "moonbit-spec-exact" => exact += 1
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
      ",\"candidate_digest\":" +
      json_string(candidate_digest) +
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
