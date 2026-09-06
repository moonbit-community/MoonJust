///|
struct Options {
  candidate : String
  target : String
  suite : String
  official : String
}

///|
struct SmokeCase {
  name : String
  justfile : String
  files : Array[(String, Bytes)]
  args : Array[String]
}

///|
struct CaseReport {
  name : String
  status : Int
  passed : Bool
  details : String
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
fn values_after(args : ArrayView[String], name : String) -> Array[String] {
  for index, value in args {
    if value == name {
      let result : Array[String] = []
      for item in args[index + 1:] {
        if item.has_prefix("--") {
          break
        }
        result.push(item)
      }
      return result
    }
  }
  []
}

///|
fn quoted_value(line : String) -> String? {
  guard line.find("\"") is Some(start) else { return None }
  let rest = line[start + 1:]
  guard rest.find("\"") is Some(end) else { return None }
  Some(rest[:end].to_owned())
}

///|
async fn module_field(name : String) -> String? {
  let text = @fs.read_file("moon.mod").text() catch { _ => "" }
  for raw in text.split("\n") {
    let line = raw.trim().to_owned()
    if line.has_prefix(name + " =") {
      return quoted_value(line)
    }
  }
  None
}

///|
fn coordinate_version(coordinate : String) -> String? {
  match coordinate.rev_find("@") {
    Some(index) if index + 1 < coordinate.length() =>
      Some(coordinate[index + 1:].to_owned())
    _ => None
  }
}

///|
fn json_string(value : String) -> String {
  "\"" +
  value
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="\"", new="\\\"")
  .replace_all(old="\n", new="\\n")
  .replace_all(old="\r", new="\\r")
  .replace_all(old="\t", new="\\t") +
  "\""
}

///|
fn asset_not_ready(status : Int, stderr : String) -> Bool {
  let diagnostic = stderr.to_lower()
  status != 0 &&
  (
    diagnostic.contains("asset") ||
    diagnostic.contains("download") ||
    diagnostic.contains("fetch") ||
    diagnostic.contains("registry") ||
    diagnostic.contains("not found") ||
    diagnostic.contains("404") ||
    diagnostic.contains("timeout") ||
    diagnostic.contains("timed out")
  )
}

///|
async fn prepare_candidate(options : Options) -> @testkit.PreparedProgram {
  @testkit.prepare_command(
    "moonx",
    ["--target", options.target, options.candidate],
    subject_path=options.candidate,
    no_console_window=false,
  )
}

///|
fn join(left : String, right : String) -> String {
  @path.Path(left).join(Path(right)).to_string()
}

///|
async fn write_case(root : String, case : SmokeCase) -> Unit {
  if !case.justfile.is_empty() {
    @fs.write_file(join(root, "justfile"), @utf8.encode(case.justfile))
  }
  for entry in case.files {
    let path = join(root, entry.0)
    let parent = @path.Path(path).dirname()
    if !@fs.exists(parent.to_string()) {
      @fs.mkdir(parent.to_string(), recursive=true)
    }
    @fs.write_file(path, entry.1)
  }
}

///|
fn normalize_bytes(root : String, bytes : Bytes) -> Bytes {
  let private_root = @utf8.encode("/private" + root)[:]
  let normalized = @testkit.replace_bytes(
    bytes,
    private_root,
    b"<CASE_ROOT>"[:],
  )
  @testkit.replace_bytes(normalized, @utf8.encode(root)[:], b"<CASE_ROOT>"[:])
}

///|
async fn append_tree(
  current : String,
  relative : String,
  root : String,
  output : StringBuilder,
) -> Unit {
  for name in @fs.readdir(current, include_hidden=true, sort=true) {
    let full = join(current, name)
    let path = if relative.is_empty() { name } else { relative + "/" + name }
    match @fs.kind(full) {
      Directory => {
        output.write_string("dir\t./" + path + "\n")
        append_tree(full, path, root, output)
      }
      Regular => {
        let bytes = normalize_bytes(root, @fs.read_file(full).binary())
        let digest = @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
        output.write_string(
          "file\t./" +
          path +
          "\t" +
          bytes.length().to_string() +
          "\t" +
          digest +
          "\n",
        )
      }
      _ => output.write_string("other\t./" + path + "\n")
    }
  }
}

///|
async fn tree_snapshot(root : String) -> String {
  let output = StringBuilder()
  append_tree(root, "", root, output)
  output.to_string()
}

///|
async fn run_once(
  program : @testkit.PreparedProgram,
  args : Array[String],
  root : String,
) -> @testkit.RunResult {
  @testkit.run_prepared(program, args, cwd=root, inherit_env=true)
}

///|
async fn compare_case(
  candidate : @testkit.PreparedProgram,
  official : @testkit.PreparedProgram,
  case : SmokeCase,
) -> CaseReport {
  let candidate_root = @fs.tmpdir(prefix="moonjust moonx candidate")
  let official_root = @fs.tmpdir(prefix="moonjust moonx official")
  defer (@fs.rmdir(candidate_root, recursive=true) catch { _ => () })
  defer (@fs.rmdir(official_root, recursive=true) catch { _ => () })
  write_case(candidate_root, case)
  write_case(official_root, case)
  let expected = run_once(official, case.args, official_root)
  let actual = run_once(candidate, case.args, candidate_root)
  let expected_stdout = normalize_bytes(official_root, expected.stdout)
  let actual_stdout = normalize_bytes(candidate_root, actual.stdout)
  let expected_stderr = normalize_bytes(official_root, expected.stderr)
  let actual_stderr = normalize_bytes(candidate_root, actual.stderr)
  let expected_tree = tree_snapshot(official_root)
  let actual_tree = tree_snapshot(candidate_root)
  let failures : Array[String] = []
  if expected.status != actual.status {
    failures.push("status")
  }
  if !@testkit.bytes_equal(expected_stdout, actual_stdout) {
    failures.push("stdout")
  }
  if !@testkit.bytes_equal(expected_stderr, actual_stderr) {
    failures.push("stderr")
  }
  if expected_tree != actual_tree {
    failures.push("tree")
  }
  let expected_failure = case.name == "recipe-failure" ||
    case.name == "fmt-check-unformatted" ||
    case.name == "no-dotenv"
  let quiet_match = case.name != "quiet" ||
    (actual.status == 0 && actual.stdout.is_empty() && actual.stderr.is_empty())
  {
    name: case.name,
    status: actual.status,
    passed: failures.is_empty() &&
    (!expected_failure || actual.status != 0) &&
    quiet_match,
    details: if failures.is_empty() {
      if expected_failure {
        "expected failure"
      } else if case.name == "quiet" {
        "silent match"
      } else {
        "match"
      }
    } else {
      "differing fields [" + failures.join(", ") + "]"
    },
  }
}

///|
async fn identity_case(
  candidate : @testkit.PreparedProgram,
  official : @testkit.PreparedProgram,
  case : SmokeCase,
  expected_version : String,
) -> CaseReport {
  let root = @fs.tmpdir(prefix="moonjust-moonx-identity")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  write_case(root, case)
  let result = run_once(candidate, case.args, root)
  let expected_result : @testkit.RunResult = if case.name == "version" {
    {
      status: 0,
      stdout: @utf8.encode("moonjust v" + expected_version + "\n"),
      stderr: Bytes::from_array([]),
    }
  } else {
    run_once(official, case.args, root)
  }
  let help_output = @utf8.decode(result.stdout) catch { _ => "" }
  let passed = if case.name == "version" {
    result.status == 0 &&
    @testkit.bytes_equal(result.stdout, expected_result.stdout) &&
    result.stderr.is_empty()
  } else if case.name == "help" {
    result.status == expected_result.status &&
    result.status == 0 &&
    result.stderr.is_empty() &&
    !help_output.is_empty() &&
    help_output.contains("--version") &&
    help_output.contains("--summary") &&
    help_output.contains("--fmt")
  } else {
    result.status == expected_result.status &&
    @testkit.bytes_equal(result.stdout, expected_result.stdout) &&
    @testkit.bytes_equal(result.stderr, expected_result.stderr)
  }
  {
    name: case.name,
    status: result.status,
    passed,
    details: if passed && case.name == "help" {
      "compatible option surface"
    } else if passed {
      "identity match"
    } else {
      "identity mismatch"
    },
  }
}

///|
fn smoke_cases() -> Array[SmokeCase] {
  let justfile = "default: hello\n\nhello:\n  echo hello\n"
  [
    { name: "default-recipe", justfile, files: [], args: [], },
    { name: "summary", justfile, files: [], args: ["--summary"], },
    { name: "list", justfile, files: [], args: ["--list"], },
    { name: "show", justfile, files: [], args: ["--show", "hello"], },
    { name: "execute", justfile, files: [], args: ["hello"], },
    {
      name: "recipe-failure",
      justfile: "fail:\n  false\n",
      files: [],
      args: ["fail"],
    },
    {
      name: "recipe-parameters",
      justfile: "greet name:\n  printf '%s\\n' \"{{name}}\"\n",
      files: [],
      args: ["greet", "MoonBit"],
    },
    {
      name: "forwarded-dash-arguments",
      justfile: "args *values:\n  printf '%s\\n' \"{{values}}\"\n",
      files: [],
      args: ["args", "--", "--flag", "value"],
    },
    { name: "dry-run", justfile, files: [], args: ["--dry-run", "hello"], },
    {
      name: "fmt-check-unformatted",
      justfile: "hello:\n echo hello\n",
      files: [],
      args: ["--fmt", "--check"],
    },
    {
      name: "fmt-check-formatted",
      justfile: "hello:\n    echo hello\n",
      files: [],
      args: ["--fmt", "--check"],
    },
    { name: "quiet", justfile, files: [], args: ["--quiet", "hello"], },
    {
      name: "no-deps",
      justfile: "a:\n  echo a\n\nb: a\n  echo b\n",
      files: [],
      args: ["--no-deps", "b"],
    },
    {
      name: "working-directory-relative-path",
      justfile: "",
      files: [("nested/justfile", b"hello:\n    echo relative\n")],
      args: [
        "--working-directory", "nested", "--justfile", "nested/justfile", "hello",
      ],
    },
    {
      name: "parallel",
      justfile: "a:\n    echo a > a.txt\n\nb:\n    echo b > b.txt\n",
      files: [],
      args: ["--quiet", "--jobs", "2", "a", "b"],
    },
    {
      name: "dotenv",
      justfile: "set dotenv-load\n\nhello:\n  printf '%s\\n' \"$GREETING\"\n",
      files: [(".env", b"GREETING=dotenv-ok\n")],
      args: ["hello"],
    },
    {
      name: "no-dotenv",
      justfile: "set dotenv-load\n\nhello:\n  echo {{env('GREETING')}}\n",
      files: [(".env", b"GREETING=dotenv-ok\n")],
      args: ["--no-dotenv", "hello"],
    },
  ]
}

///|
async fn run_cache_case(
  candidate : @testkit.PreparedProgram,
  official : @testkit.PreparedProgram,
) -> CaseReport {
  let justfile = "[cache]\n[script]\ncached:\n  echo cached\n"
  let candidate_root = @fs.tmpdir(prefix="moonjust moonx cache candidate")
  let official_root = @fs.tmpdir(prefix="moonjust moonx cache official")
  defer (@fs.rmdir(candidate_root, recursive=true) catch { _ => () })
  defer (@fs.rmdir(official_root, recursive=true) catch { _ => () })
  let case = {
    name: "cache",
    justfile,
    files: [],
    args: ["--unstable", "cached"],
  }
  write_case(candidate_root, case)
  write_case(official_root, case)
  let candidate_first = run_once(candidate, case.args, candidate_root)
  let official_first = run_once(official, case.args, official_root)
  let candidate_hit = run_once(candidate, case.args, candidate_root)
  let official_hit = run_once(official, case.args, official_root)
  let candidate_no_cache = run_once(
    candidate,
    ["--unstable", "--no-cache", "cached"],
    candidate_root,
  )
  let official_no_cache = run_once(
    official,
    ["--unstable", "--no-cache", "cached"],
    official_root,
  )
  let candidate_clean = run_once(
    candidate,
    ["--unstable", "--clean"],
    candidate_root,
  )
  let official_clean = run_once(
    official,
    ["--unstable", "--clean"],
    official_root,
  )
  let passed = candidate_first.status == official_first.status &&
    candidate_hit.status == official_hit.status &&
    candidate_no_cache.status == official_no_cache.status &&
    candidate_clean.status == official_clean.status &&
    @testkit.bytes_equal(candidate_first.stdout, official_first.stdout) &&
    @testkit.bytes_equal(candidate_first.stderr, official_first.stderr) &&
    @testkit.bytes_equal(candidate_hit.stdout, official_hit.stdout) &&
    @testkit.bytes_equal(candidate_hit.stderr, official_hit.stderr) &&
    @testkit.bytes_equal(candidate_no_cache.stdout, official_no_cache.stdout) &&
    @testkit.bytes_equal(candidate_no_cache.stderr, official_no_cache.stderr) &&
    @testkit.bytes_equal(candidate_clean.stdout, official_clean.stdout) &&
    @testkit.bytes_equal(candidate_clean.stderr, official_clean.stderr)
  {
    name: "cache",
    status: candidate_hit.status,
    passed,
    details: if passed {
      "first/hit/no-cache/clean match"
    } else {
      "cache lifecycle mismatch"
    },
  }
}

///|
async fn preflight(
  candidate : @testkit.PreparedProgram,
  expected_version : String,
  moon_home : String?,
) -> (Bool, String) {
  let expected = @utf8.encode("moonjust v" + expected_version + "\n")
  let delays = [5000, 10000, 20000, 30000]
  let mut last = "MoonX asset is not ready"
  for attempt in 0..<=delays.length() {
    let result = @testkit.run_prepared(
      candidate,
      ["--version"],
      cwd=@env.current_dir().unwrap_or("."),
      extra_env=match moon_home {
        Some(path) => { "MOON_HOME": path }
        None => Map([])
      },
      inherit_env=true,
    )
    if result.status == 0 &&
      result.stderr.is_empty() &&
      @testkit.bytes_equal(result.stdout, expected) {
      return (true, "ready")
    }
    let stderr = @utf8.decode(result.stderr) catch { _ => "<non-utf8>" }
    let not_ready = asset_not_ready(result.status, stderr)
    last = (if not_ready {
        "asset not ready"
      } else {
        "published artifact failed identity check"
      }) +
      ": attempt " +
      (attempt + 1).to_string() +
      " status=" +
      result.status.to_string() +
      " stderr=" +
      stderr
    if !not_ready {
      return (false, last)
    }
    if attempt < delays.length() {
      @async.sleep(delays[attempt])
    }
  }
  (false, last)
}

///|
async fn run_full_compat(
  options : Options,
  report : String,
  moon_home : String,
) -> @testkit.RunResult {
  let build_reentry = @testkit.run(
    "moon",
    ["build", "--release", "--target", "native", "./tests/wasm_reentry"],
    inherit_env=true,
  )
  if build_reentry.status != 0 {
    return build_reentry
  }
  let shard_count = 8
  let results = @async.with_task_group() <| group => {
    let tasks : Array[@async.Task[@testkit.RunResult]] = []
    for shard_index in 0..<shard_count {
      tasks.push(
        group.spawn(() => {
          run_full_compat_shard(
            options,
            report + ".shard-" + shard_index.to_string() + ".json",
            moon_home,
            shard_count,
            shard_index,
          )
        }),
      )
    }
    let completed : Array[@testkit.RunResult] = []
    for task in tasks {
      completed.push(task.wait())
    }
    completed
  }
  let stdout = StringBuilder()
  let stderr = StringBuilder()
  let mut status = 0
  for result in results {
    if result.status != 0 {
      status = result.status
    }
    stdout.write_string(@utf8.decode(result.stdout) catch { _ => "<non-utf8>" })
    stderr.write_string(@utf8.decode(result.stderr) catch { _ => "<non-utf8>" })
  }
  {
    status,
    stdout: @utf8.encode(stdout.to_string()),
    stderr: @utf8.encode(stderr.to_string()),
  }
}

///|
async fn run_full_compat_shard(
  options : Options,
  report : String,
  moon_home : String,
  shard_count : Int,
  shard_index : Int,
) -> @testkit.RunResult {
  @testkit.run(
    "moon",
    [
      "run",
      "--target",
      "native",
      "./tests/compat",
      "--",
      "--candidate",
      options.candidate,
      "--candidate-runner",
      "moonx",
      "--official",
      options.official,
      "--strict-coverage",
      "--allow-deferred-platform",
      "--shard-count",
      shard_count.to_string(),
      "--shard-index",
      shard_index.to_string(),
      "--wasm-reentry",
      "_build/native/release/build/tests/wasm_reentry/wasm_reentry.exe",
      "--execution-target",
      options.target,
      "--coverage-report",
      report,
    ],
    extra_env={
      "MOONJUST_MOON_HOME": moon_home,
      "MOONJUST_MOONX": "moonx",
      "MOONJUST_MOONX_TARGET": options.target,
    },
    inherit_env=true,
  )
}

///|
fn report_json(
  options : Options,
  reports : Array[CaseReport],
  full : @testkit.RunResult?,
) -> String {
  let rows : Array[String] = []
  for report in reports {
    rows.push(
      "{\"name\":" +
      json_string(report.name) +
      ",\"status\":" +
      report.status.to_string() +
      ",\"passed\":" +
      report.passed.to_string() +
      ",\"details\":" +
      json_string(report.details) +
      "}",
    )
  }
  let full_json = match full {
    Some(result) =>
      ",\"full_status\":" +
      result.status.to_string() +
      ",\"full_stdout\":" +
      json_string(@utf8.decode(result.stdout) catch { _ => "<non-utf8>" }) +
      ",\"full_stderr\":" +
      json_string(@utf8.decode(result.stderr) catch { _ => "<non-utf8>" })
    None => ""
  }
  let cases_passed = reports.all(fn(report) { report.passed })
  let full_passed = match full {
    Some(result) => result.status == 0
    None => true
  }
  "{\"candidate\":" +
  json_string(options.candidate) +
  ",\"target\":" +
  json_string(options.target) +
  ",\"suite\":" +
  json_string(options.suite) +
  ",\"passed\":" +
  (cases_passed && full_passed).to_string() +
  ",\"cases\":[" +
  rows.join(",") +
  "]" +
  full_json +
  "}\n"
}

///|
fn failure_report_json(
  options : Options,
  stage : String,
  details : String,
) -> String {
  "{\"candidate\":" +
  json_string(options.candidate) +
  ",\"target\":" +
  json_string(options.target) +
  ",\"suite\":" +
  json_string(options.suite) +
  ",\"passed\":false,\"stage\":" +
  json_string(stage) +
  ",\"details\":" +
  json_string(details) +
  "}\n"
}

///|
async fn write_report(path : String?, content : String) -> Unit {
  match path {
    Some(output) => @fs.write_file(output, @utf8.encode(content))
    None => ()
  }
}

///|
async fn aggregate_reports(args : ArrayView[String], report : String?) -> Unit {
  let paths = values_after(args, "--reports")
  guard !paths.is_empty() else {
    @stdio.stderr.write("aggregate mode requires --reports PATH...\n")
    @sys.exit(2)
    return
  }
  let failures : Array[String] = []
  for path in paths {
    let text = @fs.read_file(path).text() catch { _ => "" }
    if text.is_empty() {
      failures.push(path + ": report is missing or empty")
    } else if text.contains("\"passed\":false") {
      failures.push(path + ": report failed")
    }
  }
  let content = "{\"suite\":\"aggregate\",\"passed\":" +
    failures.is_empty().to_string() +
    ",\"reports\":[" +
    paths.map(json_string).join(",") +
    "]}\n"
  write_report(report, content)
  for failure in failures {
    @stdio.stderr.write("FAIL " + failure + "\n")
  }
  if !failures.is_empty() {
    @sys.exit(1)
  }
  @stdio.stdout.write(
    "PASS aggregate " + paths.length().to_string() + " reports\n",
  )
}

///|
async fn main {
  let args = @env.args()[1:]
  let candidate = option(args, "--candidate")
  let target = option(args, "--target").unwrap_or("wasm")
  let suite = option(args, "--suite").unwrap_or("smoke")
  let official = option(args, "--official").unwrap_or("just")
  let report = option(args, "--report")
  guard target == "wasm" || target == "native" else {
    @stdio.stderr.write("target must be `wasm` or `native`\n")
    @sys.exit(2)
    return
  }
  guard suite == "smoke" ||
    suite == "full" ||
    suite == "not-applicable" ||
    suite == "aggregate" ||
    suite == "validate-publish" else {
    @stdio.stderr.write(
      "suite must be `smoke`, `full`, `not-applicable`, `aggregate`, or `validate-publish`\n",
    )
    @sys.exit(2)
    return
  }
  let module_name = module_field("name").unwrap_or("")
  let version = module_field("version").unwrap_or("")
  let expected_coordinate = module_name + "@" + version
  if suite == "not-applicable" {
    write_report(report, "{\"suite\":\"not-applicable\",\"passed\":true}\n")
    @stdio.stdout.write("PASS not-applicable MoonX was not invoked\n")
    return
  }
  if suite == "aggregate" {
    aggregate_reports(args, report)
    return
  }
  if suite == "validate-publish" {
    let channel = option(args, "--channel").unwrap_or("")
    let valid = (channel == "rc" && version.contains("-rc.")) ||
      (channel == "stable" && !version.contains("-"))
    if !valid {
      @stdio.stderr.write(
        "publish channel/version mismatch: channel=" +
        channel +
        " version=" +
        version +
        "\n",
      )
      @sys.exit(1)
      return
    }
    @stdio.stdout.write("PASS publish validation " + expected_coordinate + "\n")
    return
  }
  let candidate_value = candidate.unwrap_or(expected_coordinate)
  guard candidate_value == expected_coordinate else {
    @stdio.stderr.write(
      "candidate must match moon.mod exactly: expected " +
      expected_coordinate +
      ", got " +
      candidate_value +
      "\n",
    )
    @sys.exit(2)
    return
  }
  guard coordinate_version(candidate_value) is Some(candidate_version) &&
    candidate_version == version else {
    @stdio.stderr.write("candidate version does not match moon.mod\n")
    @sys.exit(2)
    return
  }
  let options : Options = {
    candidate: candidate_value,
    target,
    suite,
    official,
  }
  let candidate_program = prepare_candidate(options)
  let official_program = @testkit.prepare_program(official)
  let (moon_home, owns_moon_home) = if suite == "full" {
    match @env.get_env_var("MOON_HOME") {
      Some(path) if !path.is_empty() => (Some(path), false)
      _ => (Some(@fs.tmpdir(prefix="moonjust-moonx-registry")), true)
    }
  } else {
    (None, false)
  }
  defer (if owns_moon_home {
    match moon_home {
      Some(path) => @fs.rmdir(path, recursive=true) catch { _ => () }
      None => ()
    }
  })
  let preflight_result = preflight(candidate_program, version, moon_home)
  guard preflight_result.0 else {
    write_report(
      report,
      failure_report_json(options, "preflight", preflight_result.1),
    )
    @stdio.stderr.write("MoonX preflight failed: " + preflight_result.1 + "\n")
    @sys.exit(1)
    return
  }
  let reports : Array[CaseReport] = []
  let identity_version = identity_case(
    candidate_program,
    official_program,
    { name: "version", justfile: "", files: [], args: ["--version"], },
    version,
  )
  reports.push(identity_version)
  let identity_help = identity_case(
    candidate_program,
    official_program,
    { name: "help", justfile: "", files: [], args: ["--help"], },
    version,
  )
  reports.push(identity_help)
  for case in smoke_cases() {
    reports.push(compare_case(candidate_program, official_program, case))
  }
  reports.push(run_cache_case(candidate_program, official_program))
  let full = if suite == "full" {
    let coverage_report = match report {
      Some(path) => path + ".compat.json"
      None => "_build/moonx-coverage.json"
    }
    Some(run_full_compat(options, coverage_report, moon_home.unwrap_or("")))
  } else {
    None
  }
  let smoke_failed = reports.any(fn(result) { !result.passed })
  let full_failed = match full {
    Some(result) => result.status != 0
    None => false
  }
  let report_text = report_json(options, reports, full)
  write_report(report, report_text)
  for result in reports {
    @stdio.stdout.write(
      (if result.passed { "PASS " } else { "FAIL " }) +
      result.name +
      " " +
      result.details +
      "\n",
    )
  }
  if smoke_failed || full_failed {
    @sys.exit(1)
  }
}
