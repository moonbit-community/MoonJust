///|
priv struct CaseMetadata {
  id : String
  cwd : String
  platform : String?
  merged : Bool
  closed_stdout : Bool
  verify_snapshot : Bool
  live_prefix : String?
  live_timeout_ms : Int32
  normalizations : Array[String]
  status : String
  compare : Array[String]
  allowed_difference : String?
  candidate_stdout_sha256 : String?
  host_inputs : Array[String]
  upstream_tests : Array[String]
  upstream_anchors : Array[String]
}

///|
priv struct CompatibilityManifest {
  schema_version : Int32
  upstream : String
  cases : Map[String, CaseMetadata]
}

///|
fn quoted_value(line : String) -> String? {
  guard line.find("\"") is Some(start) else { return None }
  let rest = line[start + 1:]
  guard rest.find("\"") is Some(end) else { return None }
  Some(rest[:end].to_owned())
}

///|
fn quoted_values(line : String) -> Array[String] {
  let result : Array[String] = []
  let mut rest = line
  while rest.find("\"") is Some(start) {
    let after_start = rest[start + 1:]
    guard after_start.find("\"") is Some(end) else { break }
    result.push(after_start[:end].to_owned())
    rest = after_start[end + 1:].to_owned()
  }
  result
}

///|
fn parse_manifest(text : String) -> CompatibilityManifest {
  let result : Map[String, CaseMetadata] = Map([])
  let mut schema_version = 0
  let mut upstream = ""
  let mut directory : String? = None
  let mut id = ""
  let mut cwd = ""
  let mut platform : String? = None
  let mut merged = false
  let mut closed_stdout = false
  let mut verify_snapshot = false
  let mut live_prefix : String? = None
  let mut live_timeout_ms = 1000
  let mut normalizations : Array[String] = []
  let mut status = "match"
  let mut compare : Array[String] = ["status", "stdout", "stderr", "tree"]
  let mut allowed_difference : String? = None
  let mut candidate_stdout_sha256 : String? = None
  let mut host_inputs : Array[String] = []
  let mut upstream_tests : Array[String] = []
  let mut upstream_anchors : Array[String] = []
  fn flush() -> Unit {
    match directory {
      Some(name) =>
        result[name] = {
          id,
          cwd,
          platform,
          merged,
          closed_stdout,
          verify_snapshot,
          live_prefix,
          live_timeout_ms,
          normalizations,
          status,
          compare,
          allowed_difference,
          candidate_stdout_sha256,
          host_inputs,
          upstream_tests,
          upstream_anchors,
        }
      None => ()
    }
  }
  for raw in text.split("\n") {
    let line = raw.trim().to_owned()
    if line == "[[case]]" {
      flush()
      directory = None
      id = ""
      cwd = ""
      platform = None
      merged = false
      closed_stdout = false
      verify_snapshot = false
      live_prefix = None
      live_timeout_ms = 1000
      normalizations = []
      status = "match"
      compare = ["status", "stdout", "stderr", "tree"]
      allowed_difference = None
      candidate_stdout_sha256 = None
      host_inputs = []
      upstream_tests = []
      upstream_anchors = []
    } else if line.has_prefix("schema_version =") {
      let text = line.strip_prefix("schema_version =").unwrap_or("").trim()
      schema_version = @string.parse_int(text) catch { _ => 0 }
    } else if line.has_prefix("upstream =") {
      upstream = quoted_value(line).unwrap_or("")
    } else if line.has_prefix("id =") {
      id = quoted_value(line).unwrap_or("")
    } else if line.has_prefix("directory =") {
      directory = quoted_value(line)
    } else if line.has_prefix("cwd =") {
      cwd = quoted_value(line).unwrap_or("")
    } else if line.has_prefix("platform =") {
      platform = quoted_value(line)
    } else if line.has_prefix("compare =") {
      merged = line.contains("\"merged\"")
      compare = quoted_values(line)
    } else if line == "closed_stdout = true" {
      closed_stdout = true
    } else if line == "verify_snapshot = true" {
      verify_snapshot = true
    } else if line.has_prefix("live_prefix =") {
      live_prefix = quoted_value(line)
    } else if line.has_prefix("live_timeout_ms =") {
      let text = line.strip_prefix("live_timeout_ms =").unwrap_or("").trim()
      live_timeout_ms = @string.parse_int(text) catch { _ => 1000 }
    } else if line.has_prefix("normalizations =") {
      normalizations = quoted_values(line)
    } else if line.has_prefix("status =") {
      status = quoted_value(line).unwrap_or("match")
    } else if line.has_prefix("allowed_difference =") {
      allowed_difference = quoted_value(line)
    } else if line.has_prefix("candidate_stdout_sha256 =") {
      candidate_stdout_sha256 = quoted_value(line)
    } else if line.has_prefix("host_inputs =") {
      host_inputs = quoted_values(line)
    } else if line.has_prefix("upstream_tests =") {
      upstream_tests = quoted_values(line)
    } else if line.has_prefix("upstream_anchors =") {
      upstream_anchors = quoted_values(line)
    }
  }
  flush()
  { schema_version, upstream, cases: result, }
}
