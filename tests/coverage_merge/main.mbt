///|
priv struct CoverageRow {
  upstream_id : String
  evidence_kind : String
  execution_state : String
  required_platform : String
}

///|
priv struct CoverageReport {
  runner_os : String
  target : String
  upstream_total : Int
  failures : Int
  known_differences : Int
  product_identity_differences : Int
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
fn int_field(fields : Map[String, Json], name : String) -> Int? {
  match fields.get(name) {
    Some(Number(value, ..)) => Some(value.to_int())
    _ => None
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
  Some({ upstream_id, evidence_kind, execution_state, required_platform, })
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
  guard int_field(fields, "schema_version") == Some(3) else {
    errors.push(path + ": report schema must be 3")
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
      Some(value) => rows.push(value)
      None => ()
    }
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
async fn main {
  let args = @env.args()[1:]
  let target = option(args, "--target").unwrap_or("")
  let output = option(args, "--output")
  let paths = report_paths(args)
  let errors : Array[String] = []
  if target != "native" && target != "wasm" {
    errors.push("--target must be `native` or `wasm`")
  }
  if paths.length() != 3 {
    errors.push("exactly three platform reports are required")
  }
  let reports : Array[CoverageReport] = []
  for path in paths {
    let text = @fs.read_file(path).text() catch {
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
  for report in reports {
    platforms.add(report.runner_os)
    if report.target != target {
      errors.push(report.runner_os + ": report target does not match")
    }
    if report.upstream_total != 2417 {
      errors.push(report.runner_os + ": upstream_total must be 2417")
    }
    if report.failures != 0 || report.known_differences != 0 {
      errors.push(report.runner_os + ": report contains compatibility failures")
    }
    if report.product_identity_differences != 2 {
      errors.push(report.runner_os + ": product identity count must be 2")
    }
    let seen : Set[String] = Set([])
    for row in report.rows {
      if seen.contains(row.upstream_id) {
        errors.push(report.runner_os + ": duplicate row " + row.upstream_id)
      } else {
        seen.add(row.upstream_id)
        let observations = rows_by_id.get(row.upstream_id).unwrap_or([])
        observations.push((report.runner_os, row))
        rows_by_id[row.upstream_id] = observations
      }
    }
    if seen.length() != 2417 {
      errors.push(report.runner_os + ": report does not contain 2417 rows")
    }
  }
  for required in ["linux", "macos", "windows"] {
    if !platforms.contains(required) {
      errors.push("missing platform report: " + required)
    }
  }
  let mut differential = 0
  let mut specs = 0
  let mut completion = 0
  let mut signal = 0
  for upstream_id, observations in rows_by_id {
    guard observations.get(0) is Some((_, first)) else { continue }
    for observation in observations {
      let (_, row) = observation
      if row.evidence_kind != first.evidence_kind ||
        row.required_platform != first.required_platform {
        errors.push(upstream_id + ": platform reports disagree on evidence")
      }
      if row.execution_state == "failed" || row.execution_state == "unexecuted" {
        errors.push(upstream_id + ": contains a failed or unexecuted result")
      }
    }
    match first.evidence_kind {
      "differential" => {
        differential += 1
        if first.required_platform == "all" {
          if observations.length() != 3 ||
            observations.any(fn(item) { item.1.execution_state != "executed" }) {
            errors.push(
              upstream_id + ": common differential did not run on all platforms",
            )
          }
        } else if !observations.any(fn(item) {
            let platform_matches = if first.required_platform == "unix" {
              item.0 == "linux" || item.0 == "macos"
            } else {
              item.0 == first.required_platform
            }
            platform_matches && item.1.execution_state == "executed"
          }) {
          errors.push(upstream_id + ": platform differential was not executed")
        }
      }
      "moonbit-spec" => {
        specs += 1
        if observations.length() != 3 ||
          observations.any(fn(item) { item.1.execution_state != "executed" }) {
          errors.push(
            upstream_id + ": MoonBit spec did not execute on all platforms",
          )
        }
      }
      "excluded-completion" | "excluded-signal" => {
        if first.evidence_kind == "excluded-completion" {
          completion += 1
        } else {
          signal += 1
        }
        if observations.any(fn(item) { item.1.execution_state != "excluded" }) {
          errors.push(upstream_id + ": excluded evidence changed state")
        }
      }
      _ => errors.push(upstream_id + ": unclassified evidence")
    }
  }
  if rows_by_id.length() != 2417 {
    errors.push(
      "merged report does not contain 2417 unique upstream identities",
    )
  }
  if differential != 1446 || specs != 916 || completion != 34 || signal != 21 {
    errors.push(
      "merged evidence category totals do not match the pinned inventory",
    )
  }
  let report = "{\"schema_version\":3,\"target\":" +
    json_string(target) +
    ",\"platforms\":[\"linux\",\"macos\",\"windows\"],\"upstream_total\":" +
    rows_by_id.length().to_string() +
    ",\"differential_declared\":" +
    differential.to_string() +
    ",\"differential_executed\":" +
    differential.to_string() +
    ",\"differential_exact\":" +
    differential.to_string() +
    ",\"differential_known_difference\":0,\"moonbit_spec_declared\":" +
    specs.to_string() +
    ",\"moonbit_spec_executed\":" +
    specs.to_string() +
    ",\"excluded_completion\":" +
    completion.to_string() +
    ",\"excluded_signal\":" +
    signal.to_string() +
    ",\"deferred_platform\":0,\"unclassified\":0" +
    ",\"failures\":" +
    errors.length().to_string() +
    "}\n"
  match output {
    Some(path) => @fs.write_file(path, @utf8.encode(report))
    None => @stdio.stdout.write(report)
  }
  for error in errors {
    @stdio.stderr.write("FAIL  " + error + "\n")
  }
  if !errors.is_empty() {
    @sys.exit(1)
  }
}
