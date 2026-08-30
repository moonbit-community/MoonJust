///|
priv struct CaseMetadata {
  id : String
  cwd : String
  merged : Bool
  live_prefix : String?
  live_timeout_ms : Int
  status : String
  compare : Array[String]
  allowed_difference : String?
  candidate_stdout_sha256 : String?
  candidate_stderr_sha256 : String?
  upstream_tests : Array[String]
}

///|
priv struct CompatibilityManifest {
  schema_version : Int
  upstream : String
  cases : Map[String, CaseMetadata]
}

///|
priv struct CaseResult {
  status : Int
  stdout : Bytes
  stderr : Bytes
  merged : Bytes?
  tree : Bytes
  live : Bool
}

///|
fn usage() -> String {
  "Usage: moonjust-compat --candidate PATH --official PATH " +
  "[--cases PATH] [--manifest PATH] [--upstream-list PATH] [--strict-coverage]"
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
fn has_flag(args : ArrayView[String], name : String) -> Bool {
  for value in args {
    if value == name {
      return true
    }
  }
  false
}

///|
fn join(left : String, right : String) -> String {
  @path.Path(left).join(Path(right)).to_string()
}

///|
fn quoted_value(line : String) -> String? {
  guard line.find("\"") is Some(start) else { return None }
  let rest = line.view(start_offset=start + 1)
  guard rest.find("\"") is Some(end) else { return None }
  Some(rest[:end].to_owned())
}

///|
fn quoted_values(line : String) -> Array[String] {
  let result : Array[String] = []
  let mut rest = line
  while rest.find("\"") is Some(start) {
    let after_start = rest.view(start_offset=start + 1)
    guard after_start.find("\"") is Some(end) else { break }
    result.push(after_start[:end].to_owned())
    rest = after_start.view(start_offset=end + 1).to_owned()
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
  let mut merged = false
  let mut live_prefix : String? = None
  let mut live_timeout_ms = 1000
  let mut status = "match"
  let mut compare : Array[String] = ["status", "stdout", "stderr", "tree"]
  let mut allowed_difference : String? = None
  let mut candidate_stdout_sha256 : String? = None
  let mut candidate_stderr_sha256 : String? = None
  let mut upstream_tests : Array[String] = []
  fn flush() -> Unit {
    match directory {
      Some(name) =>
        result[name] = {
          id,
          cwd,
          merged,
          live_prefix,
          live_timeout_ms,
          status,
          compare,
          allowed_difference,
          candidate_stdout_sha256,
          candidate_stderr_sha256,
          upstream_tests,
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
      merged = false
      live_prefix = None
      live_timeout_ms = 1000
      status = "match"
      compare = ["status", "stdout", "stderr", "tree"]
      allowed_difference = None
      candidate_stdout_sha256 = None
      candidate_stderr_sha256 = None
      upstream_tests = []
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
    } else if line.has_prefix("compare =") {
      merged = line.contains("\"merged\"")
      compare = quoted_values(line)
    } else if line.has_prefix("live_prefix =") {
      live_prefix = quoted_value(line)
    } else if line.has_prefix("live_timeout_ms =") {
      let text = line.strip_prefix("live_timeout_ms =").unwrap_or("").trim()
      live_timeout_ms = @string.parse_int(text) catch { _ => 1000 }
    } else if line.has_prefix("status =") {
      status = quoted_value(line).unwrap_or("match")
    } else if line.has_prefix("allowed_difference =") {
      allowed_difference = quoted_value(line)
    } else if line.has_prefix("candidate_stdout_sha256 =") {
      candidate_stdout_sha256 = quoted_value(line)
    } else if line.has_prefix("candidate_stderr_sha256 =") {
      candidate_stderr_sha256 = quoted_value(line)
    } else if line.has_prefix("upstream_tests =") {
      upstream_tests = quoted_values(line)
    }
  }
  flush()
  { schema_version, upstream, cases: result, }
}

///|
fn expand(value : String, root : String) -> String {
  value
  .replace_all(old="<CASE_ROOT>", new=root)
  .replace_all(old="<TAB>", new="\t")
  .replace_all(old="<TWO_SPACES>", new="  ")
}

///|
async fn read_text(path : String) -> String {
  @fs.read_file(path).text() catch {
    _ => ""
  }
}

///|
async fn read_optional_bytes(path : String) -> Bytes {
  if @fs.exists(path) {
    @fs.read_file(path).binary()
  } else {
    b""
  }
}

///|
async fn arguments(case_dir : String, root : String) -> Array[String] {
  let path = join(case_dir, "argv.txt")
  if !@fs.exists(path) {
    return []
  }
  let result : Array[String] = []
  for line in read_text(path).split("\n") {
    if !line.is_empty() {
      result.push(expand(line.to_owned(), root))
    }
  }
  result
}

///|
async fn environment(case_dir : String, root : String) -> Map[String, String] {
  let values : Map[String, String] = Map([])
  values["PATH"] = @env.get_env_var("PATH").unwrap_or("/usr/bin:/bin")
  values["HOME"] = join(root, "home")
  values["LC_ALL"] = "C"
  values["LANG"] = "C"
  values["TZ"] = "UTC"
  values["JUST_COLOR"] = "never"
  let path = join(case_dir, "env.list")
  if !@fs.exists(path) {
    return values
  }
  for line in read_text(path).split("\n") {
    guard !line.is_empty() && line.find("=") is Some(index) else { continue }
    let name = line[:index].to_owned()
    let value = line[index + 1:].to_owned()
    values[name] = expand(value, root)
  }
  values
}

///|
async fn copy_tree(source : String, destination : String) -> Unit {
  if !@fs.exists(source) {
    return
  }
  if !@fs.exists(destination) {
    @fs.mkdir(destination, recursive=true)
  }
  for name in @fs.readdir(source, include_hidden=true, sort=true) {
    let from = join(source, name)
    let to = join(destination, name)
    match @fs.kind(from) {
      Directory => copy_tree(from, to)
      Regular => @fs.write_file(to, @fs.read_file(from))
      _ => ()
    }
  }
}

///|
async fn prepare_root(case_dir : String, root : String, cwd : String) -> Unit {
  if !@fs.exists(join(root, "home")) {
    @fs.mkdir(join(root, "home"), recursive=true)
  }
  copy_tree(join(case_dir, "tree"), root)
  if !cwd.is_empty() {
    if !@fs.exists(join(root, cwd)) {
      @fs.mkdir(join(root, cwd), recursive=true)
    }
  }
}

///|
fn append_bytes(output : Array[Byte], input : BytesView) -> Unit {
  for byte in input {
    output.push(byte)
  }
}

///|
async fn append_tree_snapshot(
  current : String,
  relative : String,
  output : Array[Byte],
) -> Unit {
  for name in @fs.readdir(current, include_hidden=true, sort=true) {
    let full = join(current, name)
    let path = if relative.is_empty() { name } else { relative + "/" + name }
    match @fs.kind(full) {
      Directory => {
        append_bytes(output, @utf8.encode("dir\t./" + path + "\n")[:])
        append_tree_snapshot(full, path, output)
      }
      Regular => {
        let bytes = @fs.read_file(full).binary()
        append_bytes(
          output,
          @utf8.encode(
            "file\t./" + path + "\t" + bytes.length().to_string() + "\n",
          )[:],
        )
        append_bytes(output, bytes[:])
        output.push(b'\n')
      }
      _ => append_bytes(output, @utf8.encode("other\t./" + path + "\n")[:])
    }
  }
}

///|
async fn tree_snapshot(root : String) -> Bytes {
  let output : Array[Byte] = []
  append_tree_snapshot(root, "", output)
  Bytes::from_array(output)
}

///|
fn normalize(bytes : Bytes, root : String) -> Bytes {
  @testkit.replace_bytes(bytes, @utf8.encode(root)[:], b"<CASE_ROOT>"[:])
}

///|
async fn run_side(
  program : String,
  case_dir : String,
  metadata : CaseMetadata,
  side : String,
) -> CaseResult {
  let root = @fs.tmpdir(prefix="moonjust-compat-" + side)
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  prepare_root(case_dir, root, metadata.cwd)
  let cwd = if metadata.cwd.is_empty() {
    root
  } else {
    join(root, metadata.cwd)
  }
  let args = arguments(case_dir, root)
  let stdin = read_optional_bytes(join(case_dir, "stdin"))
  let env = environment(case_dir, root)
  let (status, stdout, stderr, live) = match metadata.live_prefix {
    Some(prefix) => {
      let result = @testkit.run_live_stdout(
        program,
        args,
        stdin,
        cwd,
        env,
        @utf8.encode(prefix),
        metadata.live_timeout_ms,
      )
      (result.status, result.stdout, result.stderr, result.observed)
    }
    None => {
      let result = @testkit.run(
        program,
        args,
        stdin~,
        cwd~,
        extra_env=env,
        inherit_env=false,
      )
      (result.status, result.stdout, result.stderr, true)
    }
  }
  let merged = if metadata.merged {
    let merged_root = @fs.tmpdir(prefix="moonjust-compat-" + side + "-merged")
    defer (@fs.rmdir(merged_root, recursive=true) catch { _ => () })
    prepare_root(case_dir, merged_root, metadata.cwd)
    let merged_cwd = if metadata.cwd.is_empty() {
      merged_root
    } else {
      join(merged_root, metadata.cwd)
    }
    let merged_args = arguments(case_dir, merged_root)
    let merged_env = environment(case_dir, merged_root)
    let result = @testkit.run_merged(
      program, merged_args, stdin, merged_cwd, merged_env,
    )
    Some(normalize(result.1, merged_root))
  } else {
    None
  }
  {
    status,
    stdout: normalize(stdout, root),
    stderr: normalize(stderr, root),
    merged,
    tree: tree_snapshot(root),
    live,
  }
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
  if compares(metadata, "status") && expected.status != actual.status {
    fields.push("status")
  }
  if compares(metadata, "stdout") &&
    !@testkit.bytes_equal(expected.stdout, actual.stdout) {
    fields.push("stdout")
  }
  if compares(metadata, "stderr") &&
    !@testkit.bytes_equal(expected.stderr, actual.stderr) {
    fields.push("stderr")
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
fn expected_difference_allowed(
  reason : String?,
  fields : ArrayView[String],
  actual : CaseResult,
  metadata : CaseMetadata,
) -> Bool {
  let expected_digest = match reason {
    Some("product-identity") if fields.length() == 1 && fields[0] == "stdout" =>
      metadata.candidate_stdout_sha256.map(digest => (digest, actual.stdout))
    Some("diagnostic-style") if fields.length() == 1 && fields[0] == "stderr" =>
      metadata.candidate_stderr_sha256.map(digest => (digest, actual.stderr))
    _ => None
  }
  match expected_digest {
    Some((expected, bytes)) =>
      @crypto.bytes_to_hex_string(@crypto.sha256(bytes)) == expected
    None => false
  }
}

///|
async fn official_is_pinned(program : String) -> Bool {
  let result = @testkit.run(program, ["--version"])
  result.status == 0 &&
  @testkit.bytes_equal(result.stdout, b"just 1.57.0\n") &&
  result.stderr.is_empty()
}

///|
fn module_version(text : String) -> String? {
  for raw in text.split("\n") {
    let line = raw.trim().to_owned()
    if line.has_prefix("version =") {
      return quoted_value(line)
    }
  }
  None
}

///|
async fn candidate_version_matches(program : String, version : String) -> Bool {
  let result = @testkit.run(program, ["--version"])
  result.status == 0 &&
  @testkit.bytes_equal(
    result.stdout,
    @utf8.encode("moonjust v" + version + "\n"),
  ) &&
  result.stderr.is_empty()
}

///|
fn upstream_test_names(text : String) -> Set[String] {
  let names : Array[String] = []
  for raw in text.split("\n") {
    let name = raw.trim().to_owned()
    if !name.is_empty() {
      names.push(name)
    }
  }
  Set(names)
}

///|
async fn resolve_program(value : String) -> String {
  if value.contains("/") || value.contains("\\") {
    @fs.realpath(value)
  } else {
    value
  }
}

///|
async fn main {
  let args = @env.args()[1:]
  guard option(args, "--candidate") is Some(candidate_value) &&
    option(args, "--official") is Some(official_value) else {
    @stdio.stderr.write(usage() + "\n")
    @sys.exit(2)
    return
  }
  let cases_root = option(args, "--cases").unwrap_or("tests/differential/cases")
  let selected_case = option(args, "--case")
  let manifest = option(args, "--manifest").unwrap_or(
    "tests/differential/cases.toml",
  )
  let upstream_list = option(args, "--upstream-list").unwrap_or(
    "tests/compatibility/upstream/just-1.57.0/test-list.txt",
  )
  let coverage_report = option(args, "--coverage-report")
  let spec_index = parse_spec_index(
    read_text(
      option(args, "--spec-index").unwrap_or(
        "tests/compatibility/upstream/just-1.57.0/spec-index.txt",
      ),
    ),
  )
  let candidate = resolve_program(candidate_value)
  let official = resolve_program(official_value)
  let parsed_manifest = parse_manifest(read_text(manifest))
  let metadata = parsed_manifest.cases
  let upstream_names = upstream_test_names(read_text(upstream_list))
  let mut matched = 0
  let mut known = 0
  let mut executed_total = 0
  let mut exact_total = 0
  let mut known_difference_total = 0
  let mut excluded_completion_total = 0
  let mut excluded_signal_total = 0
  let mut selected_found = false
  let failures : Array[String] = []
  let expected_version = module_version(read_text("moon.mod"))
  match expected_version {
    Some(version) if candidate_version_matches(candidate, version) => ()
    Some(version) =>
      failures.push(
        "candidate --version does not match moon.mod (expected moonjust v" +
        version +
        ")",
      )
    None => failures.push("moon.mod does not declare a product version")
  }
  if !official_is_pinned(official) {
    failures.push("official oracle must report exactly `just 1.57.0`")
  }
  if parsed_manifest.schema_version != 3 {
    failures.push("compatibility manifest schema_version must be 3")
  }
  if parsed_manifest.upstream != "just 1.57.0" {
    failures.push("compatibility manifest upstream must be `just 1.57.0`")
  }
  for name, details in metadata {
    if details.status != "match" && details.status != "expected-difference" {
      failures.push(name + ": invalid manifest status " + details.status)
    }
    for required in ["status", "stdout", "stderr", "tree"] {
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
    if details.status == "expected-difference" &&
      details.allowed_difference is None {
      failures.push(name + ": expected difference has no named reason")
    }
    if details.status == "expected-difference" &&
      details.candidate_stdout_sha256 is None &&
      details.candidate_stderr_sha256 is None {
      failures.push(name + ": expected difference has no candidate digest")
    }
    for upstream_test in details.upstream_tests {
      if !upstream_names.contains(upstream_test) {
        failures.push(
          name +
          ": upstream anchor is absent from pinned just test list: " +
          upstream_test,
        )
      }
    }
  }
  for upstream_test, spec in spec_index {
    let fixture_file = spec.fixture.split(":").collect().get(0).unwrap_or("")
    if fixture_file.is_empty() || !@fs.exists(fixture_file) {
      failures.push(
        upstream_test + ": spec fixture is missing: " + spec.fixture,
      )
    }
    if spec.anchor.is_empty() {
      failures.push(
        upstream_test + ": spec is missing an upstream source anchor",
      )
    }
  }
  // Count coverage by upstream row, rather than by local fixture count. A
  // future full corpus can provide explicit exclusion files; until then every
  // unbound upstream row remains visible as unclassified.
  for upstream_test in upstream_names {
    let (status, _, _, _) = coverage_status(upstream_test, metadata, spec_index)
    match status {
      "differential-exact" => {
        executed_total += 1
        exact_total += 1
      }
      "differential-known-difference" => {
        executed_total += 1
        known_difference_total += 1
      }
      "moonbit-spec-exact" => {
        executed_total += 1
        exact_total += 1
      }
      "excluded-completion" => excluded_completion_total += 1
      "excluded-signal" => excluded_signal_total += 1
      _ => ()
    }
  }
  match coverage_report {
    Some(path) =>
      @fs.write_file(
        path,
        @utf8.encode(coverage_json(upstream_names, metadata, spec_index)),
      )
    None => ()
  }
  for name in @fs.readdir(cases_root, include_hidden=false, sort=true) {
    if selected_case is Some(selected) && name != selected {
      continue
    }
    selected_found = true
    let case_dir = join(cases_root, name)
    if @fs.kind(case_dir) != Directory {
      continue
    }
    let details = metadata
      .get(name)
      .unwrap_or({
        cwd: "",
        merged: false,
        live_prefix: None,
        live_timeout_ms: 1000,
        id: "",
        status: "match",
        compare: ["status", "stdout", "stderr", "tree"],
        allowed_difference: None,
        candidate_stdout_sha256: None,
        candidate_stderr_sha256: None,
        upstream_tests: [],
      })
    if details.id.is_empty() {
      failures.push(name + ": missing manifest identity")
      continue
    }
    let compat_id = read_text(join(case_dir, "compat-id")).trim().to_owned()
    if compat_id != details.id {
      failures.push(
        name +
        ": manifest id " +
        details.id +
        " does not match compat-id " +
        compat_id,
      )
      continue
    }
    let expected = run_side(official, case_dir, details, "official")
    let actual = run_side(candidate, case_dir, details, "candidate")
    let differences = difference_fields(expected, actual, details)
    let expectation = read_text(join(case_dir, "expectation")).trim().to_owned()
    let expected_status = if details.status == "expected-difference" {
      "difference"
    } else {
      "match"
    }
    if expectation != expected_status {
      failures.push(
        name +
        ": expectation file says " +
        expectation +
        ", manifest says " +
        expected_status,
      )
    } else if expectation == "match" && differences.is_empty() {
      matched += 1
      @stdio.stdout.write("PASS  " + name + "\n")
    } else if expectation == "difference" &&
      expected_difference_allowed(
        details.allowed_difference,
        differences,
        actual,
        details,
      ) {
      known += 1
      @stdio.stdout.write(
        "XDIFF " + name + " [" + differences.join(", ") + "]\n",
      )
    } else {
      failures.push(
        name +
        ": expected " +
        expectation +
        ", differing fields [" +
        differences.join(", ") +
        "]",
      )
    }
  }
  for name, _ in metadata {
    if !@fs.exists(join(cases_root, name)) {
      failures.push(name + ": manifest case directory is missing")
    }
  }
  if selected_case is Some(selected) && !selected_found {
    failures.push("requested case does not exist: " + selected)
  }
  for failure in failures {
    @stdio.stderr.write("FAIL  " + failure + "\n")
  }
  @stdio.stdout.write(
    "matched=" +
    matched.to_string() +
    " known_differences=" +
    known.to_string() +
    " failures=" +
    failures.length().to_string() +
    " version=" +
    (if failures.is_empty() { "pass" } else { "fail" }) +
    " upstream_total=" +
    upstream_names.length().to_string() +
    " executed_total=" +
    executed_total.to_string() +
    " exact_total=" +
    exact_total.to_string() +
    " known_difference_total=" +
    known_difference_total.to_string() +
    " excluded_completion_total=" +
    excluded_completion_total.to_string() +
    " excluded_signal_total=" +
    excluded_signal_total.to_string() +
    " unclassified_total=" +
    (upstream_names.length() -
    executed_total -
    excluded_completion_total -
    excluded_signal_total).to_string() +
    "\n",
  )
  if has_flag(args, "--strict-coverage") &&
    upstream_names.length() !=
    executed_total + excluded_completion_total + excluded_signal_total {
    @stdio.stderr.write("FAIL  upstream coverage is incomplete\n")
    @sys.exit(1)
  }
  if !failures.is_empty() {
    @sys.exit(1)
  }
}
