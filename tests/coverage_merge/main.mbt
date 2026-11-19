///|
priv struct CoverageRow {
  upstream_id : String
  evidence_kind : String
  execution_state : String
  required_platform : String
  status : String
  reason : String
  scope : String
  fixture : String
  anchor : String
  local_test : String
}

///|
priv struct CoverageReport {
  runner_os : String
  target : String
  upstream_total : Int32
  failures : Int32
  known_differences : Int32
  product_identity_differences : Int32
  rows : Array[CoverageRow]
}

///|
fn option(args : ArrayView[String], name : String) -> String? {
  for index, value in args {
    if value == name && index + 1 < args.length() {
      return Some(args[index + 1])
    }
  }
  None
}

///|
fn report_paths(args : ArrayView[String]) -> Array[String] {
  let result : Array[String] = []
  let mut skip = false
  for value in args {
    if skip {
      skip = false
    } else if value == "--target" || value == "--output" {
      skip = true
    } else if !value.has_prefix("--") {
      result.push(value)
    }
  }
  result
}

///|
fn string_field(fields : Map[String, Json], name : String) -> String? {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn int_field(fields : Map[String, Json], name : String) -> Int32? {
  match fields.get(name) {
    Some(Number(value, ..)) => Some(value.to_int())
    _ => None
  }
}

///|
fn expected_execution(
  kind : String,
  required : String,
  platform : String,
) -> String {
  match kind {
    "host-limited" => "deferred-host"
    "repository-only" | "excluded-completion" | "excluded-signal" => "excluded"
    "differential" if required != "all" &&
      required != platform &&
      !(required == "unix" && ["macos", "linux"].contains(platform)) =>
      "deferred-platform"
    _ => "executed"
  }
}

///|
fn parse_row(
  value : Json,
  errors : Array[String],
  path : String,
) -> CoverageRow? {
  guard value is Object(fields) else {
    errors.push(path + ": coverage row is not an object")
    return None
  }
  guard string_field(fields, "upstream_id") is Some(upstream_id) &&
    string_field(fields, "evidence_kind") is Some(evidence_kind) &&
    string_field(fields, "execution_state") is Some(execution_state) &&
    string_field(fields, "required_platform") is Some(required_platform) else {
    errors.push(path + ": coverage row is missing a required field")
    return None
  }
  guard string_field(fields, "status") is Some(status) &&
    string_field(fields, "fixture") is Some(fixture) &&
    string_field(fields, "upstream_source_anchor") is Some(anchor) &&
    string_field(fields, "evidence_scope") is Some(scope) &&
    string_field(fields, "local_test") is Some(local_test) else {
    errors.push(upstream_id + ": missing evidence fields")
    return None
  }
  let reason = string_field(fields, "difference_reason").unwrap_or("")
  let valid_kind = match evidence_kind {
    "host-limited" =>
      status == evidence_kind &&
      @testkit.deferred_host_behavior(upstream_id) ==
      Some((required_platform, scope))
    "differential" =>
      status == "differential-exact" ||
      status == "differential-known-difference"
    "moonbit-spec"
    | "local-smoke"
    | "document-oracle"
    | "repository-only"
    | "excluded-completion"
    | "excluded-signal" => status == evidence_kind
    _ => false
  }
  if !valid_kind {
    errors.push(upstream_id + ": invalid evidence kind or status")
  }
  if fixture.is_empty() ||
    anchor.is_empty() ||
    (
      ["local-smoke", "document-oracle", "repository-only"].contains(
        evidence_kind,
      ) &&
      scope.is_empty()
    ) ||
    (
      ["local-smoke", "moonbit-spec"].contains(evidence_kind) &&
      local_test.is_empty()
    ) {
    errors.push(upstream_id + ": missing evidence location, test or scope")
  }
  if !["all", "unix", "linux", "macos", "windows"].contains(required_platform) {
    errors.push(
      upstream_id + ": unknown required platform " + required_platform,
    )
  }
  if status == "differential-known-difference" {
    let digest = string_field(fields, "candidate_digest")
    if digest is None ||
      @testkit.allowed_stderr_digest(
        upstream_id, fixture, reason, required_platform,
      ) !=
      digest {
      errors.push(upstream_id + ": difference is not on the reviewed allowlist")
    }
  }
  Some({
    upstream_id,
    evidence_kind,
    execution_state,
    required_platform,
    status,
    reason,
    scope,
    fixture,
    anchor,
    local_test,
  })
}

///|
fn parse_report(
  text : String,
  path : String,
  errors : Array[String],
) -> CoverageReport? {
  let value = @json.parse(text[:]) catch {
    _ => {
      errors.push(path + ": invalid JSON")
      return None
    }
  }
  guard value is Object(fields) else {
    errors.push(path + ": report root is not an object")
    return None
  }
  guard int_field(fields, "schema_version") == Some(4) else {
    errors.push(path + ": report schema must be 4")
    return None
  }
  guard string_field(fields, "runner_os") is Some(runner_os) &&
    string_field(fields, "target") is Some(target) &&
    int_field(fields, "upstream_total") is Some(upstream_total) &&
    int_field(fields, "failures") is Some(failures) &&
    int_field(fields, "differential_known_difference") is Some(known) &&
    int_field(fields, "product_identity_difference") is Some(identity) &&
    fields.get("rows") is Some(Array(values)) else {
    errors.push(path + ": report is missing a required summary field")
    return None
  }
  let rows : Array[CoverageRow] = []
  for row in values {
    match parse_row(row, errors, path) {
      Some(value) => {
        if value.execution_state !=
          expected_execution(
            value.evidence_kind,
            value.required_platform,
            runner_os,
          ) {
          errors.push(
            value.upstream_id + ": unexpected execution state on " + runner_os,
          )
        }
        rows.push(value)
      }
      None => ()
    }
  }
  for
    (kind, prefix) in [
      ("moonbit-spec", "moonbit_spec"),
      ("local-smoke", "local_smoke"),
      ("document-oracle", "document_oracle"),
    ] {
    let matching = rows.filter(r => r.evidence_kind == kind)
    if int_field(fields, prefix + "_declared") != Some(matching.length()) ||
      int_field(fields, prefix + "_executed") !=
      Some(matching.filter(r => r.execution_state == "executed").length()) {
      errors.push(path + ": summary disagrees with rows for " + kind)
    }
  }
  if int_field(fields, "repository_only") !=
    Some(rows.filter(r => r.evidence_kind == "repository-only").length()) {
    errors.push(path + ": summary disagrees with repository-only rows")
  }
  Some({
    runner_os,
    target,
    upstream_total,
    failures,
    known_differences: known,
    product_identity_differences: identity,
    rows,
  })
}

///|
fn json_string(value : String) -> String {
  "\"" +
  value.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"") +
  "\""
}

///|
async fn reject_invalid_evidence(errors : Array[String]) -> Unit {
  if !errors.is_empty() {
    for error in errors {
      @stdio.stderr.text.write("FAIL  " + error + "\n")
    }
    @env.exit(1)
  }
}

///|
async fn main {
  let args = @env.args()[1:]
  let target = option(args, "--target").unwrap_or("wasm")
  let output = option(args, "--output")
  let paths = report_paths(args)
  let errors : Array[String] = []
  if target != "wasm" {
    errors.push("--target must be `wasm`")
  }
  if paths.length() != 3 {
    errors.push("exactly three platform reports are required")
  }
  let reports : Array[CoverageReport] = []
  for path in paths {
    let text = @fs.read_text(path) catch {
      _ => {
        errors.push(path + ": cannot read report")
        continue
      }
    }
    match parse_report(text, path, errors) {
      Some(report) => reports.push(report)
      None => ()
    }
  }
  let platforms : Set[String] = Set([])
  let rows_by_id : Map[String, Array[(String, CoverageRow)]] = Map([])
  let inventory = Set::from_iter(
    @fs.read_text("tests/compatibility/upstream/just-1.59.0/test-list.txt")
    .split("\n")
    .map(id => id.trim().to_owned())
    .filter(id => !id.is_empty()),
  )
  for report in reports {
    if platforms.contains(report.runner_os) {
      errors.push("duplicate platform report: " + report.runner_os)
    }
    platforms.add(report.runner_os)
    if report.target != target {
      errors.push(report.runner_os + ": report target does not match")
    }
    if report.upstream_total != inventory.length() {
      errors.push(
        report.runner_os + ": upstream_total differs from the pinned inventory",
      )
    }
    if report.failures != 0 ||
      report.known_differences !=
      report.rows
      .filter(row => {
        row.status == "differential-known-difference" &&
        row.execution_state == "executed"
      })
      .length() {
      errors.push(report.runner_os + ": report contains compatibility failures")
    }
    if report.product_identity_differences != 2 {
      errors.push(report.runner_os + ": product identity count must be 2")
    }
    let seen : Set[String] = Set([])
    for row in report.rows {
      if !inventory.contains(row.upstream_id) {
        errors.push(
          report.runner_os + ": unknown upstream identity " + row.upstream_id,
        )
      }
      if seen.contains(row.upstream_id) {
        errors.push(report.runner_os + ": duplicate row " + row.upstream_id)
      } else {
        seen.add(row.upstream_id)
        let observations = rows_by_id.get(row.upstream_id).unwrap_or([])
        observations.push((report.runner_os, row))
        rows_by_id[row.upstream_id] = observations
      }
    }
    if seen.length() != inventory.length() {
      errors.push(
        report.runner_os + ": row count differs from the pinned inventory",
      )
    }
  }
  for required in ["linux", "macos", "windows"] {
    if !platforms.contains(required) {
      errors.push("missing platform report: " + required)
    }
  }
  reject_invalid_evidence(errors)
  let mut known = 0
  let mut differential = 0
  let mut specs = 0
  let mut smoke = 0
  let mut documents = 0
  let mut repository_only = 0
  let mut completion = 0
  let mut signal = 0
  let mut host_limited = 0
  for upstream_id, observations in rows_by_id {
    guard observations.get(0) is Some((_, first)) else { continue }
    for observation in observations {
      let (_, row) = observation
      if row.evidence_kind != first.evidence_kind ||
        row.status != first.status ||
        row.reason != first.reason ||
        row.scope != first.scope ||
        row.fixture != first.fixture ||
        row.anchor != first.anchor ||
        row.local_test != first.local_test ||
        row.required_platform != first.required_platform {
        errors.push(upstream_id + ": platform reports disagree on evidence")
      }
    }
    match first.evidence_kind {
      "differential" => {
        differential += 1
        if first.status == "differential-known-difference" {
          known += 1
        }
      }
      "moonbit-spec" => specs += 1
      "local-smoke" => smoke += 1
      "document-oracle" => documents += 1
      "repository-only" => repository_only += 1
      "excluded-completion" => completion += 1
      "excluded-signal" => signal += 1
      "host-limited" => host_limited += 1
      _ => errors.push(upstream_id + ": unclassified evidence")
    }
  }
  if rows_by_id.length() != inventory.length() {
    errors.push("merged identity count differs from the pinned inventory")
  }
  if differential != 1446 ||
    specs != 906 ||
    smoke != 4 ||
    documents != 3 ||
    repository_only != 3 ||
    completion != 39 ||
    host_limited != 1 ||
    signal != 21 {
    errors.push(
      "merged evidence category totals do not match the pinned inventory",
    )
  }
  reject_invalid_evidence(errors)
  let report = "{\"schema_version\":4,\"target\":" +
    json_string(target) +
    ",\"platforms\":[\"linux\",\"macos\",\"windows\"],\"upstream_total\":" +
    rows_by_id.length().to_string() +
    ",\"differential_declared\":" +
    differential.to_string() +
    ",\"differential_executed\":" +
    differential.to_string() +
    ",\"differential_exact\":" +
    (differential - known).to_string() +
    ",\"differential_known_difference\":" +
    known.to_string() +
    ",\"moonbit_spec_declared\":" +
    specs.to_string() +
    ",\"moonbit_spec_executed\":" +
    specs.to_string() +
    ",\"local_smoke_declared\":" +
    smoke.to_string() +
    ",\"local_smoke_executed\":" +
    smoke.to_string() +
    ",\"document_oracle_declared\":" +
    documents.to_string() +
    ",\"document_oracle_executed\":" +
    documents.to_string() +
    ",\"repository_only\":" +
    repository_only.to_string() +
    ",\"product_identity_difference\":2" +
    ",\"excluded_completion\":" +
    completion.to_string() +
    ",\"excluded_signal\":" +
    signal.to_string() +
    ",\"host_limited\":" +
    host_limited.to_string() +
    ",\"deferred_platform\":0,\"unclassified\":0,\"failures\":0}\n"
  match output {
    Some(path) => @fs.write_binary(path, @utf8.encode(report))
    None => @stdio.stdout.text.write(report)
  }
}
