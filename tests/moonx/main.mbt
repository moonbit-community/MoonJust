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
  status : Int32
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
fn quoted_value(line : String) -> String? {
  guard line.find("\"") is Some(start) else { return None }
  let rest = line[start + 1:]
  guard rest.find("\"") is Some(end) else { return None }
  Some(rest[:end].to_owned())
}

///|
async fn module_field(name : String) -> String? {
  let text = @fs.read_text("moon.mod") catch { _ => "" }
  for raw in text.split("\n") {
    let line = raw.trim().to_owned()
    if line.has_prefix(name + " =") {
      return quoted_value(line)
    }
  }
  None
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
fn asset_not_ready(status : Int32, stderr : String) -> Bool {
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
async fn prepare_candidate(coordinate : String) -> @testkit.PreparedProgram {
  @testkit.prepare_command(
    "moonx",
    ["--target", "wasm", coordinate],
    subject_path=coordinate,
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
    @fs.write_binary(join(root, "justfile"), @utf8.encode(case.justfile))
  }
  for entry in case.files {
    let path = join(root, entry.0)
    let parent = @path.Path(path).dirname()
    if !@fs.exists(parent.to_string()) {
      @fs.mkdir(parent.to_string(), recursive=true)
    }
    @fs.write_binary(path, entry.1)
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
        let bytes = normalize_bytes(root, @fs.read_binary(full))
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
  extra_env~ : Map[String, String] = Map([]),
) -> @testkit.RunResult {
  @testkit.run_prepared(program, args, cwd=root, extra_env~, inherit_env=true)
}

///|
async fn compare_case(
  candidate : @testkit.PreparedProgram,
  official : @testkit.PreparedProgram,
  case : SmokeCase,
) -> CaseReport {
  let candidate_root = @fs.tmpdir(prefix="moonjust moonx candidate")
  let official_root = @fs.tmpdir(prefix="moonjust moonx official")
  defer (@fs.remove(candidate_root, recursive=true) catch { _ => () })
  defer (@fs.remove(official_root, recursive=true) catch { _ => () })
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
  if (actual.status != 0) != expected_failure {
    failures.push("unexpected exit status")
  }
  if case.name == "quiet" &&
    (!actual.stdout.is_empty() || !actual.stderr.is_empty()) {
    failures.push("quiet output")
  }
  {
    name: case.name,
    status: actual.status,
    passed: failures.is_empty(),
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
  defer (@fs.remove(root, recursive=true) catch { _ => () })
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
  defer (@fs.remove(candidate_root, recursive=true) catch { _ => () })
  defer (@fs.remove(official_root, recursive=true) catch { _ => () })
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
  let passed = [
      candidate_first, candidate_hit, candidate_no_cache, candidate_clean, official_first,
      official_hit, official_no_cache, official_clean,
    ].all(result => result.status == 0) &&
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
) -> (Bool, String) {
  let expected = @utf8.encode("moonjust v" + expected_version + "\n")
  let delays = [5000, 10000, 20000, 30000]
  let mut last = "MoonX asset is not ready"
  for attempt in 0..<=delays.length() {
    let result = @testkit.run_prepared(
      candidate,
      ["--version"],
      cwd=@env.current_dir().unwrap_or("."),
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
fn report_json(coordinate : String, reports : Array[CaseReport]) -> String {
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
  "{\"candidate\":" +
  json_string(coordinate) +
  ",\"target\":\"wasm\",\"host\":" +
  json_string(@testkit.runner_os()) +
  ",\"passed\":" +
  reports.all(report => report.passed).to_string() +
  ",\"cases\":[" +
  rows.join(",") +
  "]}\n"
}

///|
fn failure_report_json(
  coordinate : String,
  stage : String,
  details : String,
) -> String {
  "{\"candidate\":" +
  json_string(coordinate) +
  ",\"target\":\"wasm\",\"host\":" +
  json_string(@testkit.runner_os()) +
  ",\"passed\":false,\"stage\":" +
  json_string(stage) +
  ",\"details\":" +
  json_string(details) +
  "}\n"
}

///|
async fn write_report(path : String?, content : String) -> Unit {
  match path {
    Some(output) => @fs.write_binary(output, @utf8.encode(content))
    None => ()
  }
}

///|
async fn main {
  let args = @env.args()[1:]
  let report = option(args, "--report")
  guard module_field("name") is Some(name) &&
    module_field("version") is Some(version) else {
    fail("moon.mod must identify a versioned module")
  }
  let coordinate = name + "@" + version
  let candidate_program = prepare_candidate(coordinate)
  let official_program = @testkit.prepare_program("just")
  let oracle = @testkit.run_prepared_bytes(official_program, ["--version"])
  guard oracle.status == 0 && oracle.stdout == b"just 1.59.0\n" else {
    fail("expected just 1.59.0")
  }
  let preflight_result = preflight(candidate_program, version)
  guard preflight_result.0 else {
    write_report(
      report,
      failure_report_json(coordinate, "preflight", preflight_result.1),
    )
    @stdio.stderr.text.write(
      "MoonX preflight failed: " + preflight_result.1 + "\n",
    )
    @env.exit(1)
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
  write_report(report, report_json(coordinate, reports))
  for result in reports {
    @stdio.stdout.text.write(
      (if result.passed { "PASS " } else { "FAIL " }) +
      result.name +
      " " +
      result.details +
      "\n",
    )
  }
  if reports.any(result => !result.passed) {
    @env.exit(1)
  }
}
