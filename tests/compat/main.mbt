///|
priv struct CaseMetadata {
  id : String
  cwd : String
  platform : String?
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
  steps : Array[StepResult]
}

///|
priv struct StepResult {
  status : Int
  stdout : Bytes
  stderr : Bytes
}

///|
fn usage() -> String {
  "Usage: moonjust-compat --candidate PATH --official PATH " +
  "[--cases PATH] [--manifest PATH] [--upstream-list PATH] " +
  "[--record-expected] [--verify-snapshots] [--strict-coverage]"
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
/// Keep runner-only symlink metadata outside the isolated project tree.
fn link_metadata_path(root : String) -> String {
  root + ".moonjust-tree-links"
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
  let mut platform : String? = None
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
          platform,
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
      platform = None
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
    } else if line.has_prefix("platform =") {
      platform = quoted_value(line)
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
fn runner_platform() -> String {
  let value = @env.get_env_var("RUNNER_OS")
    .unwrap_or(
      @env.get_env_var("OS").unwrap_or(
        @env.get_env_var("OSTYPE").unwrap_or("unix"),
      ),
    )
    .to_lower()
  if value.contains("windows") || value == "windows_nt" {
    "windows"
  } else if value.contains("mac") || value.contains("darwin") {
    "macos"
  } else {
    "linux"
  }
}

///|
fn platform_matches(platform : String?, current : String) -> Bool {
  match platform {
    None => true
    Some(expected) => expected.to_lower() == current
  }
}

///|
fn strip_cr(line : StringView) -> StringView {
  line.strip_suffix("\r").unwrap_or(line)
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
async fn read_optional_text(path : String) -> String? {
  if @fs.exists(path) {
    let text = @fs.read_file(path).text()
    let text = text.strip_suffix("\n").unwrap_or(text[:])
    let text = text.strip_suffix("\r").unwrap_or(text)
    Some(text.to_owned())
  } else {
    None
  }
}

///|
fn concatenate_step_stream(
  steps : ArrayView[StepResult],
  use_stdout : Bool,
) -> Bytes {
  let output : Array[Byte] = []
  for step in steps {
    append_bytes(
      output,
      if use_stdout {
        step.stdout[:]
      } else {
        step.stderr[:]
      },
    )
  }
  Bytes::from_array(output)
}

///|
async fn write_expected(case_dir : String, result : CaseResult) -> Unit {
  @fs.write_file(
    join(case_dir, "expected.status"),
    @utf8.encode(result.status.to_string() + "\n"),
  )
  @fs.write_file(join(case_dir, "expected.stdout"), result.stdout)
  @fs.write_file(join(case_dir, "expected.stderr"), result.stderr)
  @fs.write_file(join(case_dir, "expected.tree"), result.tree)
  match result.merged {
    Some(bytes) => @fs.write_file(join(case_dir, "expected.merged"), bytes)
    None => ()
  }
  let steps_root = join(case_dir, "steps")
  if @fs.exists(steps_root) {
    let names = @fs.readdir(steps_root, include_hidden=false, sort=true)
    for index, name in names {
      guard result.steps.get(index) is Some(step) else { continue }
      let directory = join(steps_root, name)
      @fs.write_file(
        join(directory, "expected.status"),
        @utf8.encode(step.status.to_string() + "\n"),
      )
      @fs.write_file(join(directory, "expected.stdout"), step.stdout)
      @fs.write_file(join(directory, "expected.stderr"), step.stderr)
    }
  }
}

///|
async fn expected_snapshot(case_dir : String) -> CaseResult? {
  let steps_root = join(case_dir, "steps")
  if @fs.exists(steps_root) {
    let steps : Array[StepResult] = []
    for name in @fs.readdir(steps_root, include_hidden=false, sort=true) {
      let directory = join(steps_root, name)
      guard @fs.kind(directory) == Directory else { continue }
      guard @fs.exists(join(directory, "expected.status")) else { return None }
      let status = @string.parse_int(
        read_text(join(directory, "expected.status")).trim(),
      ) catch {
        _ => return None
      }
      steps.push({
        status,
        stdout: @fs.read_file(join(directory, "expected.stdout")).binary(),
        stderr: @fs.read_file(join(directory, "expected.stderr")).binary(),
      })
    }
    guard !steps.is_empty() else { return None }
    return Some({
      status: steps[steps.length() - 1].status,
      stdout: concatenate_step_stream(steps, true),
      stderr: concatenate_step_stream(steps, false),
      merged: None,
      tree: @fs.read_file(join(case_dir, "expected.tree")).binary(),
      live: true,
      steps,
    })
  }
  guard @fs.exists(join(case_dir, "expected.status")) else { return None }
  let status = @string.parse_int(
    read_text(join(case_dir, "expected.status")).trim(),
  ) catch {
    _ => return None
  }
  let merged = if @fs.exists(join(case_dir, "expected.merged")) {
    Some(@fs.read_file(join(case_dir, "expected.merged")).binary())
  } else {
    None
  }
  let stdout = @fs.read_file(join(case_dir, "expected.stdout")).binary()
  let stderr = @fs.read_file(join(case_dir, "expected.stderr")).binary()
  Some({
    status,
    stdout,
    stderr,
    merged,
    tree: @fs.read_file(join(case_dir, "expected.tree")).binary(),
    live: true,
    steps: [{ status, stdout, stderr, }],
  })
}

///|
async fn arguments(case_dir : String, root : String) -> Array[String] {
  let path = join(case_dir, "argv.txt")
  if !@fs.exists(path) {
    return []
  }
  let result : Array[String] = []
  for raw in read_text(path).split("\n") {
    let line = strip_cr(raw)
    if line == "<EMPTY>" {
      result.push("")
    } else if !line.is_empty() {
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
  for raw in read_text(path).split("\n") {
    let line = strip_cr(raw)
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
async fn apply_symlinks(directory : String, root : String) -> Unit {
  let descriptor = join(directory, "symlinks.list")
  if !@fs.exists(descriptor) {
    return
  }
  let link_metadata = link_metadata_path(root)
  for raw in read_text(descriptor).split("\n") {
    let fields = raw.split("\t").collect()
    if fields.length() < 2 {
      continue
    }
    @fs.symlink(
      join(root, fields[0].to_owned()).view(),
      target=fields[1].view(),
      force_symlink=true,
    )
    // A fixture may mark a host executable symlink as a tree link. Recording
    // the target keeps snapshots portable without copying ELF/Mach-O bytes.
    if fields.length() >= 3 && fields[2] == "link" {
      let existing = if @fs.exists(link_metadata) {
        @fs.read_file(link_metadata).text()
      } else {
        ""
      }
      @fs.write_file(
        link_metadata,
        @utf8.encode(
          existing + fields[0].to_owned() + "\t" + fields[1].to_owned() + "\n",
        ),
      )
    }
  }
}

///|
async fn apply_expanded_files(directory : String, root : String) -> Unit {
  let descriptor = join(directory, "expand.list")
  if !@fs.exists(descriptor) {
    return
  }
  for raw in read_text(descriptor).split("\n") {
    let relative = raw.trim().to_owned()
    if relative.is_empty() {
      continue
    }
    let path = join(root, relative)
    let text = @fs.read_file(path).text()
    @fs.write_file(path, @utf8.encode(expand(text, root)))
  }
}

///|
async fn apply_directories(directory : String, root : String) -> Unit {
  let descriptor = join(directory, "directories.list")
  if !@fs.exists(descriptor) {
    return
  }
  for raw in read_text(descriptor).split("\n") {
    let relative = raw.trim().to_owned()
    if !relative.is_empty() {
      @fs.mkdir(join(root, relative), recursive=true)
    }
  }
}

///|
async fn apply_trimmed_files(directory : String, root : String) -> Unit {
  let descriptor = join(directory, "trim-final-newline.list")
  if !@fs.exists(descriptor) {
    return
  }
  for raw in read_text(descriptor).split("\n") {
    let relative = raw.trim().to_owned()
    if relative.is_empty() {
      continue
    }
    let path = join(root, relative)
    let bytes = @fs.read_file(path).binary()
    if bytes.length() > 0 && bytes[bytes.length() - 1] == b'\n' {
      @fs.write_file(path, bytes[:bytes.length() - 1].to_owned())
    }
  }
}

///|
async fn prepare_root(case_dir : String, root : String, cwd : String) -> Unit {
  if !@fs.exists(join(root, "home")) {
    @fs.mkdir(join(root, "home"), recursive=true)
  }
  copy_tree(join(case_dir, "tree"), root)
  apply_directories(case_dir, root)
  apply_trimmed_files(case_dir, root)
  if !cwd.is_empty() && !@fs.exists(join(root, cwd)) {
    @fs.mkdir(join(root, cwd), recursive=true)
  }
  apply_expanded_files(case_dir, root)
  apply_symlinks(case_dir, root)
}

///|
async fn apply_step_changes(step_dir : String, root : String) -> Unit {
  copy_tree(join(step_dir, "write"), root)
  apply_directories(step_dir, root)
  apply_trimmed_files(step_dir, root)
  apply_expanded_files(step_dir, root)
  apply_symlinks(step_dir, root)
  let remove = join(step_dir, "remove.list")
  if @fs.exists(remove) {
    for raw in read_text(remove).split("\n") {
      let relative = raw.trim().to_owned()
      if relative.is_empty() {
        continue
      }
      let path = join(root, relative)
      @fs.rmdir(path, recursive=true) catch {
        _ => @fs.remove(path.view()) catch { _ => () }
      }
    }
  }
}

///|
async fn run_steps(
  program : String,
  case_dir : String,
  root : String,
  cwd : String,
) -> Array[StepResult] {
  let result : Array[StepResult] = []
  let steps_root = join(case_dir, "steps")
  for name in @fs.readdir(steps_root, include_hidden=false, sort=true) {
    let step_dir = join(steps_root, name)
    guard @fs.kind(step_dir) == Directory else { continue }
    apply_step_changes(step_dir, root)
    let args = arguments(step_dir, root)
    let stdin = read_optional_bytes(join(step_dir, "stdin"))
    let env = environment(step_dir, root)
    let execution = @testkit.run(
      program,
      args,
      stdin~,
      cwd~,
      extra_env=env,
      inherit_env=false,
    )
    result.push({
      status: execution.status,
      stdout: normalize(execution.stdout, root),
      stderr: normalize(execution.stderr, root),
    })
  }
  result
}

///|
fn append_bytes(output : Array[Byte], input : BytesView) -> Unit {
  for byte in input {
    output.push(byte)
  }
}

///|
fn normalized_tree_path(path : String, bytes : BytesView) -> String {
  guard path.has_prefix(".justcache/") && path.has_suffix(".json") else {
    return path
  }
  let name = path
    .strip_prefix(".justcache/")
    .unwrap_or(path)
    .strip_suffix(".json")
    .unwrap_or("")
  if name.length() == 64 &&
    name.all(fn(character) {
      character.is_ascii_digit() || (character >= 'a' && character <= 'f')
    }) {
    let text = @utf8.decode(bytes) catch { _ => "" }
    let recipe = match text.find("\"recipe\":\"") {
      Some(start) => {
        let tail = text.view(start_offset=start + 10)
        match tail.find("\"") {
          Some(end) => tail[:end].to_owned()
          None => "unknown"
        }
      }
      None => "unknown"
    }
    ".justcache/<CACHE_KEY-" + recipe + ">.json"
  } else {
    path
  }
}

///|
async fn append_tree_snapshot(
  current : String,
  relative : String,
  output : Array[Byte],
  root : String,
  links : Map[String, String],
) -> Unit {
  if relative == ".justcache" {
    let entries : Array[(String, Bytes)] = []
    for name in @fs.readdir(current, include_hidden=true, sort=true) {
      let full = join(current, name)
      if @fs.kind(full) == Regular {
        entries.push((name, @fs.read_file(full).binary()))
      }
    }
    entries.sort_by(fn(left, right) {
      normalized_tree_path(".justcache/" + left.0, left.1[:]).compare(
        normalized_tree_path(".justcache/" + right.0, right.1[:]),
      )
    })
    for _, entry in entries {
      let name = entry.0
      let raw_bytes = entry.1
      let bytes = normalize(raw_bytes, root)
      let path = normalized_tree_path(".justcache/" + name, raw_bytes[:])
      append_bytes(
        output,
        @utf8.encode(
          "file\t./" + path + "\t" + bytes.length().to_string() + "\n",
        )[:],
      )
      append_bytes(output, bytes[:])
      output.push(b'\n')
    }
    return
  }
  for name in @fs.readdir(current, include_hidden=true, sort=true) {
    let full = join(current, name)
    let raw_path = if relative.is_empty() {
      name
    } else {
      relative + "/" + name
    }
    match links.get(raw_path) {
      Some(target) => {
        append_bytes(
          output,
          @utf8.encode("link\t./" + raw_path + "\t" + target + "\n")[:],
        )
        continue
      }
      None => ()
    }
    match @fs.kind(full) {
      Directory => {
        append_bytes(output, @utf8.encode("dir\t./" + raw_path + "\n")[:])
        append_tree_snapshot(full, raw_path, output, root, links)
      }
      Regular => {
        let bytes = normalize(@fs.read_file(full).binary(), root)
        let path = normalized_tree_path(raw_path, bytes[:])
        append_bytes(
          output,
          @utf8.encode(
            "file\t./" + path + "\t" + bytes.length().to_string() + "\n",
          )[:],
        )
        append_bytes(output, bytes[:])
        output.push(b'\n')
      }
      _ => append_bytes(output, @utf8.encode("other\t./" + raw_path + "\n")[:])
    }
  }
}

///|
async fn tree_snapshot(root : String) -> Bytes {
  let output : Array[Byte] = []
  let links : Map[String, String] = Map([])
  let metadata = link_metadata_path(root)
  if @fs.exists(metadata) {
    for line in @fs.read_file(metadata).text().split("\n") {
      let fields = line.split("\t").collect()
      if fields.length() == 2 && !fields[0].is_empty() {
        links[fields[0].to_owned()] = fields[1].to_owned()
      }
    }
  }
  append_tree_snapshot(root, "", output, root, links)
  Bytes::from_array(output)
}

///|
fn normalize(bytes : Bytes, root : String) -> Bytes {
  let private_root = @utf8.encode("/private" + root)[:]
  let normalized = @testkit.replace_bytes(
    bytes,
    private_root,
    b"<CASE_ROOT>"[:],
  )
  let normalized = @testkit.replace_bytes(
    normalized,
    @utf8.encode(root)[:],
    b"<CASE_ROOT>"[:],
  )
  @testkit.replace_bytes(normalized, b"/private/tmp/"[:], b"/tmp/"[:])
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
  defer (@fs.remove(link_metadata_path(root).view()) catch { _ => () })
  prepare_root(case_dir, root, metadata.cwd)
  let cwd = if metadata.cwd.is_empty() {
    root
  } else {
    join(root, metadata.cwd)
  }
  let steps_root = join(case_dir, "steps")
  if @fs.exists(steps_root) {
    let steps = run_steps(program, case_dir, root, cwd)
    let last = steps[steps.length() - 1]
    return {
      status: last.status,
      stdout: concatenate_step_stream(steps, true),
      stderr: concatenate_step_stream(steps, false),
      merged: None,
      tree: normalize(tree_snapshot(root), root),
      live: true,
      steps,
    }
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
    tree: normalize(tree_snapshot(root), root),
    live,
    steps: [
      {
        status,
        stdout: normalize(stdout, root),
        stderr: normalize(stderr, root),
      },
    ],
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
  stdout_regex : String?,
  stderr_regex : String?,
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
      stdout_regex is None &&
      !@testkit.bytes_equal(expected_step.stdout, actual_step.stdout) &&
      !fields.contains("stdout") {
      fields.push("stdout")
    }
    if compares(metadata, "stderr") &&
      stderr_regex is None &&
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
  let stdout_differs = match stdout_regex {
    Some(pattern) => !regex_matches(pattern, actual.stdout)
    None => !@testkit.bytes_equal(expected.stdout, actual.stdout)
  }
  if compares(metadata, "stdout") && stdout_differs {
    if !fields.contains("stdout") {
      fields.push("stdout")
    }
  }
  let stderr_differs = match stderr_regex {
    Some(pattern) => !regex_matches(pattern, actual.stderr)
    None => !@testkit.bytes_equal(expected.stderr, actual.stderr)
  }
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
fn regex_matches(pattern : String, bytes : Bytes) -> Bool {
  let normalized = pattern.replace_all(old="(?s)", new="")
  let regexp = @regexp.compile(normalized[:]) catch { _ => return false }
  let text = @utf8.decode(bytes) catch { _ => return false }
  regexp.execute(text[:]).matched()
}

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
  @stdio.stderr.write(
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
    @stdio.stderr.write(
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
  let names : Set[String] = Set([])
  for raw in text.split("\n") {
    let name = raw.trim().to_owned()
    if !name.is_empty() {
      names.add(name)
    }
  }
  names
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
  let record_expected = has_flag(args, "--record-expected")
  let verify_snapshots = has_flag(args, "--verify-snapshots")
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
  let fixture_cache : Map[String, String] = Map([])
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
    for required in ["status", "stdout", "stderr"] {
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
    let fixture_file = spec.fixture
      .split(":")
      .collect()
      .get(0)
      .unwrap_or("")
      .to_owned()
    if !upstream_names.contains(upstream_test) {
      failures.push(
        upstream_test +
        ": spec index entry is absent from pinned just test list",
      )
    }
    if fixture_file.is_empty() || !@fs.exists(fixture_file) {
      failures.push(
        upstream_test + ": spec fixture is missing: " + spec.fixture,
      )
    }
    if !fixture_file.is_empty() &&
      @fs.exists(fixture_file) &&
      !audited_fixture(upstream_test, fixture_file, spec.anchor, fixture_cache) {
      failures.push(
        upstream_test +
        ": upstream fixture must contain source-backed input and expected sections",
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
        platform: None,
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
    if !platform_matches(details.platform, runner_platform()) {
      @stdio.stdout.write(
        "SKIP  " + name + " (platform=" + details.platform.unwrap_or("") + ")\n",
      )
      continue
    }
    let stdout_regex = read_optional_text(join(case_dir, "stdout.regex"))
    let stderr_regex = read_optional_text(join(case_dir, "stderr.regex"))
    let official_result = run_side(official, case_dir, details, "official")
    match stdout_regex {
      Some(pattern) if !regex_matches(pattern, official_result.stdout) =>
        failures.push(name + ": official stdout does not match stdout.regex")
      _ => ()
    }
    match stderr_regex {
      Some(pattern) if !regex_matches(pattern, official_result.stderr) =>
        failures.push(name + ": official stderr does not match stderr.regex")
      _ => ()
    }
    if record_expected {
      write_expected(case_dir, official_result)
    }
    let expected_snapshot_result = expected_snapshot(case_dir)
    match expected_snapshot_result {
      Some(snapshot) if verify_snapshots && !record_expected => {
        let snapshot_differences = difference_fields(
          snapshot, official_result, details, stdout_regex, stderr_regex,
        )
        if !snapshot_differences.is_empty() {
          failures.push(
            name +
            ": recorded official result differs in [" +
            snapshot_differences.join(", ") +
            "]",
          )
        }
      }
      Some(_) => ()
      None => failures.push(name + ": missing expected result snapshot")
    }
    // The live official oracle is authoritative on every runner. Recorded
    // snapshots document the fixture and are optionally audited on the same
    // platform with --verify-snapshots.
    let expected = official_result
    let actual = run_side(candidate, case_dir, details, "candidate")
    let differences = difference_fields(
      expected, actual, details, stdout_regex, stderr_regex,
    )
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
      write_difference_details(name, differences, expected, actual)
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
