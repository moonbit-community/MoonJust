///|
priv struct SpecCase {
  fixture : String
  anchor : String
  local_test : String?
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
      let local_test = if fields.length() >= 4 && !fields[2].trim().is_empty() {
        Some(fields[2].trim().to_owned())
      } else {
        None
      }
      let anchor = if fields.length() >= 4 {
        fields[3].to_owned()
      } else {
        fields[2].to_owned()
      }
      result[fields[0].to_owned()] = {
        fixture: fields[1].to_owned(),
        anchor,
        local_test,
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
  let completion_protocol_tests = [
    "config::tests::completions_argument", "config::tests::subcommand_completions",
    "config::tests::subcommand_completions_invalid", "config::tests::subcommand_completions_uppercase",
  ]
  let runtime_signal_tests = [
    "no_exit_message::signal_exit_message_not_suppressed", "no_exit_message::signal_exit_message_setting_suppressed",
    "no_exit_message::signal_exit_message_suppressed", "choose::chooser_signal_exit_code_is_propagated",
  ]
  if upstream_test.has_prefix("completions::") ||
    completion_protocol_tests.contains(upstream_test) {
    Some("completion generation protocol is shell-specific")
  } else if upstream_test.has_prefix("signals::") ||
    upstream_test.has_prefix("signal::") ||
    runtime_signal_tests.contains(upstream_test) {
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
    for index, declared in details.upstream_tests {
      if declared != upstream_test {
        continue
      }
      let status = if details.status == "match" {
        "differential-exact"
      } else {
        "differential-known-difference"
      }
      let reason = details.allowed_difference.unwrap_or("")
      let anchor = details.upstream_anchors.get(index).unwrap_or("")
      return (status, name, anchor, reason)
    }
  }
  // Explicitly excluded upstream suites remain excluded even when their
  // source snapshot is present. They depend on shell completion or OS signal
  // identity rather than MoonJust's portable command semantics.
  match excluded_reason(upstream_test) {
    Some(reason) if upstream_test.has_prefix("completions::") ||
      upstream_test == "config::tests::completions_argument" ||
      upstream_test == "config::tests::subcommand_completions" ||
      upstream_test == "config::tests::subcommand_completions_invalid" ||
      upstream_test == "config::tests::subcommand_completions_uppercase" => {
      let evidence = specs.get(upstream_test)
      return (
        "excluded-completion",
        evidence.map(fn(spec) { spec.fixture }).unwrap_or(upstream_test),
        evidence.map(fn(spec) { spec.anchor }).unwrap_or(""),
        reason,
      )
    }
    Some(reason) => {
      let evidence = specs.get(upstream_test)
      return (
        "excluded-signal",
        evidence.map(fn(spec) { spec.fixture }).unwrap_or(upstream_test),
        evidence.map(fn(spec) { spec.anchor }).unwrap_or(""),
        reason,
      )
    }
    None => ()
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
  ("unclassified", "", "", "")
}

///|
/// Extract a `path:line` location without accepting a missing or non-numeric
/// line number. Fixture paths in this index are repository-relative and do not
/// contain a colon.
fn location_parts(location : String) -> (String, Int)? {
  guard location.find(":") is Some(separator) else { return None }
  let path = location[:separator].to_owned()
  let line = @string.parse_int(location[separator + 1:]) catch {
    _ => return None
  }
  if path.is_empty() || line < 1 {
    None
  } else {
    Some((path, line))
  }
}

///|
/// Read the quoted name from a MoonBit test declaration.
fn test_name(line : String) -> String? {
  guard line.find("test \"") is Some(start) else { return None }
  let rest = line[start + 6:]
  guard rest.find("\"") is Some(end) else { return None }
  Some(rest[:end].to_owned())
}

///|
/// Validate a local spec anchor against the actual test declaration. Source
/// snapshots intentionally have no local test and are validated separately by
/// `audited_fixture`.
async fn validate_spec_anchor(
  upstream_test : String,
  spec : SpecCase,
) -> String? {
  let fixture_path = match location_parts(spec.fixture) {
    Some((path, _)) => path
    None => return Some(upstream_test + ": invalid local fixture location")
  }
  if fixture_path.has_suffix("upstream-fixtures.txt") {
    return None
  }
  guard @fs.exists(fixture_path) else {
    return Some(upstream_test + ": local spec file is missing: " + fixture_path)
  }
  let (_, line) = location_parts(spec.fixture).unwrap()
  let lines = @fs.read_file(fixture_path).text().split("\n").collect()
  if line > lines.length() {
    return Some(
      upstream_test + ": local spec line is out of range: " + spec.fixture,
    )
  }
  let mut declaration : String? = None
  let mut declaration_line = 0
  for index, raw in lines {
    match test_name(raw.to_owned()) {
      Some(name) => {
        declaration = Some(name)
        declaration_line = index + 1
      }
      None => ()
    }
    if index + 1 > line {
      break
    }
  }
  guard declaration is Some(name) else {
    return Some(upstream_test + ": local spec anchor is outside a test block")
  }
  if declaration_line > line {
    return Some(
      upstream_test + ": local spec anchor is before a test declaration",
    )
  }
  match spec.local_test {
    Some(expected) if name != expected =>
      Some(
        upstream_test +
        ": local test name mismatch: expected `" +
        expected +
        "`, found `" +
        name +
        "`",
      )
    Some(_) => None
    None => None
  }
}

///|
async fn validate_upstream_anchor(
  upstream_test : String,
  anchor : String,
) -> String? {
  guard location_parts(anchor) is Some((relative, line_number)) else {
    return Some(upstream_test + ": invalid upstream source anchor")
  }
  let source = "tests/compatibility/upstream/just-1.57.0/source/" + relative
  guard @fs.exists(source) else {
    return Some(upstream_test + ": upstream source file is missing: " + source)
  }
  let lines = @fs.read_file(source).text().split("\n").collect()
  guard line_number <= lines.length() else {
    return Some(upstream_test + ": upstream source line is out of range")
  }
  let name = upstream_test.split("::").collect().last().unwrap_or("")
  if name.is_empty() || !lines[line_number - 1].contains(name) {
    Some(upstream_test + ": upstream source line does not name the test")
  } else {
    None
  }
}

///|
/// Validate the tabular index before entries are placed in a map. A map would
/// otherwise silently overwrite duplicate upstream identities.
fn spec_index_shape_errors(text : String) -> Array[String] {
  let errors : Array[String] = []
  let seen : Set[String] = Set([])
  let seen_local : Set[String] = Set([])
  for raw in text.split("\n") {
    let line = raw.trim().to_owned()
    if line.is_empty() || line.has_prefix("#") {
      continue
    }
    let fields = line.split("\t").collect()
    if fields.length() != 4 {
      errors.push(
        "spec-index row must contain four tab-separated fields: " + line,
      )
      continue
    }
    let upstream_test = fields[0].to_owned()
    if upstream_test.is_empty() {
      errors.push("spec-index row has an empty upstream identity")
    } else if seen.contains(upstream_test) {
      errors.push("duplicate spec-index upstream identity: " + upstream_test)
    } else {
      seen.add(upstream_test)
    }
    let fixture_path = fields[1]
      .to_owned()
      .split(":")
      .collect()
      .get(0)
      .unwrap_or("")
      .to_owned()
    let is_snapshot = fixture_path.has_suffix("upstream-fixtures.txt")
    if location_parts(fields[1].to_owned()) is None && !is_snapshot {
      errors.push(upstream_test + ": invalid local fixture location")
    }
    if !is_snapshot && fields[2].trim().is_empty() {
      errors.push(upstream_test + ": missing local test name")
    }
    if !is_snapshot {
      let local_key = fields[1].to_owned() + "\t" + fields[2].to_owned()
      if seen_local.contains(local_key) {
        errors.push(upstream_test + ": duplicate local test mapping")
      } else {
        seen_local.add(local_key)
      }
    }
    let source_anchor = fields[3]
    if location_parts(source_anchor.to_owned()) is None {
      errors.push(upstream_test + ": invalid upstream source anchor")
    }
  }
  errors
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
  block.contains("\nsource: " + anchor + "\n") &&
  block.contains("\ninput:\n") &&
  block.contains("\nexpected:\n")
}

///|
fn coverage_json(
  upstream_names : Set[String],
  metadata : Map[String, CaseMetadata],
  specs : Map[String, SpecCase],
  executed : Set[String],
  exact : Set[String],
  known : Set[String],
  failed : Set[String],
  deferred : Set[String],
  spec_executed : Set[String],
  failures : Int,
  execution_platform : String,
  execution_target : String,
) -> String {
  let rows : Array[String] = []
  let mut differential_declared = 0
  let mut differential_executed = 0
  let mut differential_exact = 0
  let mut differential_known = 0
  let mut spec_declared = 0
  let mut spec_done = 0
  let mut completion = 0
  let mut signal = 0
  let mut deferred_count = 0
  let mut unclassified = 0
  let mut product_identity = 0
  for upstream_test in upstream_names {
    let (status, fixture, anchor, reason) = coverage_status(
      upstream_test, metadata, specs,
    )
    let is_differential = status == "differential-exact" ||
      status == "differential-known-difference"
    if is_differential {
      differential_declared += 1
    }
    if is_differential && executed.contains(upstream_test) {
      differential_executed += 1
    }
    if status == "differential-exact" && exact.contains(upstream_test) {
      differential_exact += 1
    }
    if status == "differential-known-difference" &&
      known.contains(upstream_test) {
      differential_known += 1
    }
    if status == "moonbit-spec-exact" {
      spec_declared += 1
      if spec_executed.contains(upstream_test) {
        spec_done += 1
      }
    }
    if deferred.contains(upstream_test) {
      deferred_count += 1
    }
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
    let evidence_kind = match status {
      "differential-exact" | "differential-known-difference" => "differential"
      "moonbit-spec-exact" => "moonbit-spec"
      "excluded-completion" => "excluded-completion"
      "excluded-signal" => "excluded-signal"
      _ => "unclassified"
    }
    let execution_state = if deferred.contains(upstream_test) {
      "deferred-platform"
    } else if failed.contains(upstream_test) {
      "failed"
    } else if executed.contains(upstream_test) ||
      spec_executed.contains(upstream_test) {
      "executed"
    } else if status == "excluded-completion" || status == "excluded-signal" {
      "excluded"
    } else {
      "unexecuted"
    }
    let required_platform = {
      let mut required = "all"
      for _, details in metadata {
        if details.upstream_tests.contains(upstream_test) {
          required = details.platform.unwrap_or("all")
          break
        }
      }
      required
    }
    match status {
      "excluded-completion" => completion += 1
      "excluded-signal" => signal += 1
      "unclassified" => unclassified += 1
      _ => ()
    }
    let fixture = if fixture.is_empty() { upstream_test } else { fixture }
    let local_test = match specs.get(upstream_test) {
      Some(spec) => spec.local_test.unwrap_or(fixture)
      None => fixture
    }
    rows.push(
      "{\"upstream_id\":" +
      json_string(upstream_test) +
      ",\"evidence_kind\":" +
      json_string(evidence_kind) +
      ",\"execution_state\":" +
      json_string(execution_state) +
      ",\"status\":" +
      json_string(status) +
      ",\"execution_platform\":" +
      json_string(execution_platform) +
      ",\"execution_target\":" +
      json_string(execution_target) +
      ",\"required_platform\":" +
      json_string(required_platform) +
      ",\"fixture\":" +
      json_string(fixture) +
      ",\"local_test\":" +
      json_string(local_test) +
      ",\"upstream_source_anchor\":" +
      json_string(anchor) +
      ",\"difference_reason\":" +
      json_string(reason) +
      ",\"candidate_digest\":" +
      json_string(candidate_digest) +
      "}",
    )
  }
  for _, details in metadata {
    if details.status == "expected-difference" &&
      details.allowed_difference == Some("product-identity") {
      product_identity += 1
    }
  }
  "{\"schema_version\":3,\"runner_os\":" +
  json_string(execution_platform) +
  ",\"target\":" +
  json_string(execution_target) +
  ",\"upstream_total\":" +
  upstream_names.length().to_string() +
  ",\"differential_declared\":" +
  differential_declared.to_string() +
  ",\"differential_executed\":" +
  differential_executed.to_string() +
  ",\"differential_exact\":" +
  differential_exact.to_string() +
  ",\"differential_known_difference\":" +
  differential_known.to_string() +
  ",\"moonbit_spec_declared\":" +
  spec_declared.to_string() +
  ",\"moonbit_spec_executed\":" +
  spec_done.to_string() +
  ",\"excluded_completion\":" +
  completion.to_string() +
  ",\"excluded_signal\":" +
  signal.to_string() +
  ",\"deferred_platform\":" +
  deferred_count.to_string() +
  ",\"unclassified\":" +
  unclassified.to_string() +
  ",\"failures\":" +
  failures.to_string() +
  ",\"product_identity_difference\":" +
  product_identity.to_string() +
  ",\"rows\":[" +
  rows.join(",") +
  "]}\n"
}
