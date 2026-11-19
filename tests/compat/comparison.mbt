///|
priv struct CaseResult {
  status : Int32
  stdout : Bytes
  stderr : Bytes
  merged : Bytes?
  tree : Bytes
  live : Bool
  steps : Array[StepResult]
}

///|
priv struct StepResult {
  status : Int32
  stdout : Bytes
  stderr : Bytes
}

///|
fn compares(metadata : CaseMetadata, field : String) -> Bool {
  metadata.compare.contains(field)
}

///|
fn difference_fields(
  expected : CaseResult,
  actual : CaseResult,
  metadata : CaseMetadata,
) -> Array[String] {
  let fields : Array[String] = []
  if expected.steps.length() != actual.steps.length() {
    fields.push("status")
    fields.push("stdout")
    fields.push("stderr")
    return fields
  }
  for index, expected_step in expected.steps {
    let actual_step = actual.steps[index]
    if compares(metadata, "status") &&
      expected_step.status != actual_step.status &&
      !fields.contains("status") {
      fields.push("status")
    }
    if compares(metadata, "stdout") &&
      !@testkit.bytes_equal(expected_step.stdout, actual_step.stdout) &&
      !fields.contains("stdout") {
      fields.push("stdout")
    }
    if compares(metadata, "stderr") &&
      !@testkit.bytes_equal(expected_step.stderr, actual_step.stderr) &&
      !fields.contains("stderr") {
      fields.push("stderr")
    }
  }
  if compares(metadata, "status") && expected.status != actual.status {
    if !fields.contains("status") {
      fields.push("status")
    }
  }
  let stdout_differs = !@testkit.bytes_equal(expected.stdout, actual.stdout)
  if compares(metadata, "stdout") && stdout_differs {
    if !fields.contains("stdout") {
      fields.push("stdout")
    }
  }
  let stderr_differs = !@testkit.bytes_equal(expected.stderr, actual.stderr)
  if compares(metadata, "stderr") && stderr_differs {
    if !fields.contains("stderr") {
      fields.push("stderr")
    }
  }
  if compares(metadata, "merged") {
    match (expected.merged, actual.merged) {
      (Some(left), Some(right)) if !@testkit.bytes_equal(left, right) =>
        fields.push("merged")
      (None, None) => ()
      (Some(_), None) | (None, Some(_)) => fields.push("merged")
      _ => ()
    }
  }
  if compares(metadata, "tree") &&
    !@testkit.bytes_equal(expected.tree, actual.tree) {
    fields.push("tree")
  }
  if compares(metadata, "live") && (!expected.live || !actual.live) {
    fields.push("live")
  }
  fields
}

///|

///|
async fn write_difference_bytes(
  case_name : String,
  field : String,
  side : String,
  bytes : Bytes,
) -> Unit {
  let limit = 4096
  let displayed = if bytes.length() > limit { bytes[:limit] } else { bytes[:] }
  let text = @utf8.decode(displayed) catch { _ => "<non-UTF-8>" }
  @stdio.stderr.text.write(
    "DIFF  " +
    case_name +
    " " +
    field +
    " " +
    side +
    " length=" +
    bytes.length().to_string() +
    " sha256=" +
    @crypto.bytes_to_hex_string(@crypto.sha256(bytes)) +
    "\n<<<\n" +
    text +
    (if bytes.length() > limit { "\n<truncated>" } else { "" }) +
    "\n>>>\n",
  )
}

///|
async fn write_difference_details(
  name : String,
  fields : ArrayView[String],
  official : CaseResult,
  candidate : CaseResult,
) -> Unit {
  if fields.contains("status") {
    @stdio.stderr.text.write(
      "DIFF  " +
      name +
      " status official=" +
      official.status.to_string() +
      " candidate=" +
      candidate.status.to_string() +
      "\n",
    )
  }
  if fields.contains("stdout") {
    write_difference_bytes(name, "stdout", "official", official.stdout)
    write_difference_bytes(name, "stdout", "candidate", candidate.stdout)
  }
  if fields.contains("stderr") {
    write_difference_bytes(name, "stderr", "official", official.stderr)
    write_difference_bytes(name, "stderr", "candidate", candidate.stderr)
  }
  if fields.contains("merged") {
    match official.merged {
      Some(bytes) => write_difference_bytes(name, "merged", "official", bytes)
      None => ()
    }
    match candidate.merged {
      Some(bytes) => write_difference_bytes(name, "merged", "candidate", bytes)
      None => ()
    }
  }
  if fields.contains("tree") {
    write_difference_bytes(name, "tree", "official", official.tree)
    write_difference_bytes(name, "tree", "candidate", candidate.tree)
  }
}

///|
fn refusal_digest(fixture : String, metadata : CaseMetadata) -> String? {
  guard metadata.upstream_tests[:] is [upstream] else { return None }
  @testkit.allowed_stderr_digest(
    upstream,
    fixture,
    metadata.allowed_difference.unwrap_or(""),
    metadata.platform.unwrap_or("all"),
  )
}

///|
fn expected_difference_allowed(
  fixture : String,
  fields : ArrayView[String],
  actual : CaseResult,
  expected : CaseResult,
  initial_tree : Bytes,
  metadata : CaseMetadata,
) -> Bool {
  let expected_digest = match metadata.allowed_difference {
    Some("product-identity") if fields.length() == 1 && fields[0] == "stdout" =>
      metadata.candidate_stdout_sha256.map(digest => (digest, actual.stdout))
    Some("atomic-format-permissions") if expected.status == 0 &&
      actual.status == 1 &&
      actual.stdout.is_empty() &&
      fields == ["status", "stderr", "tree"] &&
      @testkit.bytes_equal(actual.tree, initial_tree) =>
      refusal_digest(fixture, metadata).map(digest => (digest, actual.stderr))
    _ => None
  }
  match expected_digest {
    Some((expected, bytes)) =>
      @crypto.bytes_to_hex_string(@crypto.sha256(bytes)) == expected
    None => false
  }
}
