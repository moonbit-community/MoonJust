///|
priv struct CaseMetadata {
  cwd : String
  merged : Bool
  live_prefix : String?
  live_timeout_ms : Int
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
  "Usage: moonjust-compat --candidate PATH --official PATH [--cases PATH] [--manifest PATH]"
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
fn metadata_from_manifest(text : String) -> Map[String, CaseMetadata] {
  let result : Map[String, CaseMetadata] = Map([])
  let mut directory : String? = None
  let mut cwd = ""
  let mut merged = false
  let mut live_prefix : String? = None
  let mut live_timeout_ms = 1000
  fn flush() -> Unit {
    match directory {
      Some(name) =>
        result[name] = { cwd, merged, live_prefix, live_timeout_ms, }
      None => ()
    }
  }
  for raw in text.split("\n") {
    let line = raw.trim().to_owned()
    if line == "[[case]]" {
      flush()
      directory = None
      cwd = ""
      merged = false
      live_prefix = None
      live_timeout_ms = 1000
    } else if line.has_prefix("directory =") {
      directory = quoted_value(line)
    } else if line.has_prefix("cwd =") {
      cwd = quoted_value(line).unwrap_or("")
    } else if line.has_prefix("compare =") {
      merged = line.contains("\"merged\"")
    } else if line.has_prefix("live_prefix =") {
      live_prefix = quoted_value(line)
    } else if line.has_prefix("live_timeout_ms =") {
      let text = line.strip_prefix("live_timeout_ms =").unwrap_or("").trim()
      live_timeout_ms = @string.parse_int(text) catch { _ => 1000 }
    }
  }
  flush()
  result
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
fn difference_fields(
  expected : CaseResult,
  actual : CaseResult,
) -> Array[String] {
  let fields : Array[String] = []
  if expected.status != actual.status {
    fields.push("status")
  }
  if !@testkit.bytes_equal(expected.stdout, actual.stdout) {
    fields.push("stdout")
  }
  if !@testkit.bytes_equal(expected.stderr, actual.stderr) {
    fields.push("stderr")
  }
  match (expected.merged, actual.merged) {
    (Some(left), Some(right)) if !@testkit.bytes_equal(left, right) =>
      fields.push("merged")
    (None, None) => ()
    (Some(_), None) | (None, Some(_)) => fields.push("merged")
    _ => ()
  }
  if !@testkit.bytes_equal(expected.tree, actual.tree) {
    fields.push("tree")
  }
  if !expected.live || !actual.live {
    fields.push("live")
  }
  fields
}

///|
fn expected_difference_allowed(
  case_name : String,
  fields : ArrayView[String],
) -> Bool {
  if fields.is_empty() {
    return false
  }
  let allowed : Array[String] = match case_name {
    "01-version" | "02-help" => ["stdout", "stderr", "merged"]
    "29-function-unstable"
    | "178-dotenv-command-filename-option-conflict"
    | "179-dotenv-command-path-option-conflict"
    | "180-dotenv-command-no-dotenv-conflict" => ["stderr", "merged"]
    _ => []
  }
  fields.all(fn(field) { allowed.contains(field) })
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
  let candidate = resolve_program(candidate_value)
  let official = resolve_program(official_value)
  let metadata = metadata_from_manifest(read_text(manifest))
  let mut matched = 0
  let mut known = 0
  let failures : Array[String] = []
  for name in @fs.readdir(cases_root, include_hidden=false, sort=true) {
    if selected_case is Some(selected) && name != selected {
      continue
    }
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
      })
    let expected = run_side(official, case_dir, details, "official")
    let actual = run_side(candidate, case_dir, details, "candidate")
    let differences = difference_fields(expected, actual)
    let expectation = read_text(join(case_dir, "expectation")).trim().to_owned()
    if expectation == "match" && differences.is_empty() {
      matched += 1
      @stdio.stdout.write("PASS  " + name + "\n")
    } else if expectation == "difference" &&
      expected_difference_allowed(name, differences) {
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
    "\n",
  )
  if !failures.is_empty() {
    @sys.exit(1)
  }
}
