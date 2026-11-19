///|
priv struct SpecCase {
  fixture : String
  anchor : String
  local_test : String?
  smoke_scope : String?
}

///|
fn parse_spec_index(text : String) -> Map[String, SpecCase] {
  let result : Map[String, SpecCase] = Map([])
  for raw in text.split("\n") {
    let line = strip_cr(raw)
    if line.trim().is_empty() || line.has_prefix("#") {
      continue
    }
    let fields = line.split("\t").collect()
    if fields.length() == 4 || fields.length() == 5 {
      let local_test = if !fields[2].trim().is_empty() {
        Some(fields[2].trim().to_owned())
      } else {
        None
      }
      result[fields[0].to_owned()] = {
        fixture: fields[1].to_owned(),
        anchor: fields[3].to_owned(),
        local_test,
        smoke_scope: fields.get(4).map(field => field.to_owned()),
      }
    }
  }
  result
}

///|
fn exclusion(upstream_test : String) -> (String, String)? {
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
    Some(
      (
        "excluded-completion", "completion generation protocol is shell-specific",
      ),
    )
  } else if upstream_test.has_prefix("signals::") ||
    upstream_test.has_prefix("signal::") ||
    runtime_signal_tests.contains(upstream_test) {
    Some(
      (
        "excluded-signal", "runtime signal identity and forwarding are OS-specific",
      ),
    )
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
  // Concrete MoonBit assertion files are executable spec evidence. The large
  // Rust source snapshot is audit evidence only and must not inflate coverage.
  if specs.get(upstream_test) is Some(spec) {
    if @testkit.deferred_host_behavior(upstream_test) is Some((_, reason)) {
      return ("host-limited", spec.fixture, spec.anchor, reason)
    }
    if exclusion(upstream_test) is Some((kind, reason)) {
      return (kind, spec.fixture, spec.anchor, reason)
    }
    if document_contract(upstream_test) is Some(doc) {
      let (kind, artifact, scope) = doc.evidence()
      return (kind, artifact, spec.anchor, scope)
    }
    let fixture_path = spec.fixture
      .split(":")
      .collect()
      .get(0)
      .unwrap_or("")
      .to_owned()
    if !fixture_path.has_suffix("upstream-fixtures.txt") &&
      spec.local_test is Some(_) {
      return match spec.smoke_scope {
        Some(scope) => ("local-smoke", spec.fixture, spec.anchor, scope)
        None => ("moonbit-spec", spec.fixture, spec.anchor, "")
      }
    }
    return ("unclassified", spec.fixture, spec.anchor, "source-snapshot-only")
  }
  ("unclassified", "", "", "")
}

///|
/// Extract a `path:line` location without accepting a missing or non-numeric
/// line number. Fixture paths in this index are repository-relative and do not
/// contain a colon.
fn location_parts(location : String) -> (String, Int32)? {
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
  let declaration = line.strip_prefix("async ").unwrap_or(line[:])
  guard declaration.strip_prefix("test \"") is Some(rest) else { return None }
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
  guard location_parts(spec.fixture) is Some((fixture_path, line)) else {
    return Some(upstream_test + ": invalid local fixture location")
  }
  if fixture_path.has_suffix("upstream-fixtures.txt") ||
    spec.fixture == DOCUMENT_ROOT + "/" + spec.anchor {
    return None
  }
  guard @fs.exists(fixture_path) else {
    return Some(upstream_test + ": local spec file is missing: " + fixture_path)
  }
  let lines = @fs.read_text(fixture_path).split("\n").collect()
  if line > lines.length() {
    return Some(
      upstream_test + ": local spec line is out of range: " + spec.fixture,
    )
  }
  guard test_name(lines[line - 1].to_owned()) is Some(name) else {
    return Some(upstream_test + ": local spec anchor is not a test declaration")
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
    None => Some(upstream_test + ": missing local test name")
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
  let source = "tests/compatibility/upstream/just-1.59.0/source/" + relative
  guard @fs.exists(source) else {
    return Some(upstream_test + ": upstream source file is missing: " + source)
  }
  let lines = @fs.read_text(source).split("\n").collect()
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
    let line = strip_cr(raw).to_owned()
    if line.trim().is_empty() || line.has_prefix("#") {
      continue
    }
    let fields = line.split("\t").collect()
    if fields.length() != 4 && fields.length() != 5 {
      errors.push(
        "spec-index row must contain four fields and an optional smoke scope: " +
        line,
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
    let provenance = fixture_path.has_suffix("upstream-fixtures.txt") ||
      fields[1] == (DOCUMENT_ROOT + "/" + fields[3].to_owned())[:]
    if fields.length() == 5 && (provenance || fields[4].trim().is_empty()) {
      errors.push(
        upstream_test +
        ": smoke scope requires an executable local assertion and a description",
      )
    }
    if location_parts(fields[1].to_owned()) is None {
      errors.push(upstream_test + ": invalid local fixture location")
    }
    if provenance && !fields[2].is_empty() {
      errors.push(upstream_test + ": provenance cannot name a local test")
    }
    if !provenance && fields[2].trim().is_empty() {
      errors.push(upstream_test + ": missing local test name")
    }
    if !provenance {
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
/// Check the indexed snapshot line, source anchor and both nonempty sections.
async fn audited_fixture(
  upstream_test : String,
  spec : SpecCase,
  cache : Map[String, Array[StringView]],
) -> Bool {
  guard location_parts(spec.fixture) is Some((fixture_file, line)) else {
    return false
  }
  if !fixture_file.has_suffix("upstream-fixtures.txt") {
    return true
  }
  let lines = match cache.get(fixture_file) {
    Some(value) => value
    None => {
      let value = @fs.read_text(fixture_file).split("\n").collect()
      cache[fixture_file] = value
      value
    }
  }
  guard line + 1 < lines.length() &&
    lines[line - 1] == ("=== " + upstream_test + " ===")[:] &&
    lines[line] == ("source: " + spec.anchor)[:] &&
    lines[line + 1] == "input:" else {
    return false
  }
  let mut input = false
  let mut expected = false
  let mut in_expected = false
  for index in (line + 2)..<lines.length() {
    match lines[index] {
      "expected:" => in_expected = true
      "=== end ===" => return input && expected
      value if value.has_prefix("=== ") => return false
      value if !value.trim().is_empty() =>
        if in_expected {
          expected = true
        } else {
          input = true
        }
      _ => ()
    }
  }
  false
}
