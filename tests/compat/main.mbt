///|
priv struct CaseMetadata {
  id : String
  cwd : String
  platform : String?
  merged : Bool
  live_prefix : String?
  live_timeout_ms : Int
  normalizations : Array[String]
  status : String
  compare : Array[String]
  allowed_difference : String?
  candidate_stdout_sha256 : String?
  candidate_stderr_sha256 : String?
  upstream_tests : Array[String]
  upstream_anchors : Array[String]
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
  "[--candidate-runner PATH] " +
  "[--cases PATH] [--manifest PATH] [--upstream-list PATH] " +
  "[--record-expected] [--verify-snapshots] [--strict-coverage] " +
  "[--allow-deferred-platform] [--wasm-reentry PATH]"
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
async fn fixture_structure_errors(
  name : String,
  case_dir : String,
) -> Array[String] {
  let errors : Array[String] = []
  for
    required in [
      "compat-id", "expectation", "expected.status", "expected.stdout", "expected.stderr",
      "expected.tree",
    ] {
    if !@fs.exists(join(case_dir, required)) {
      errors.push(name + ": fixture is missing required file " + required)
    }
  }
  if !@fs.exists(join(case_dir, "argv.txt")) &&
    !@fs.exists(join(case_dir, "steps")) {
    errors.push(name + ": fixture has no explicit argv or step input")
  }
  if @fs.exists(join(case_dir, "stdout.regex")) ||
    @fs.exists(join(case_dir, "stderr.regex")) {
    errors.push(name + ": regex expectations are forbidden")
  }
  errors
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
  let mut normalizations : Array[String] = []
  let mut status = "match"
  let mut compare : Array[String] = ["status", "stdout", "stderr", "tree"]
  let mut allowed_difference : String? = None
  let mut candidate_stdout_sha256 : String? = None
  let mut candidate_stderr_sha256 : String? = None
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
          live_prefix,
          live_timeout_ms,
          normalizations,
          status,
          compare,
          allowed_difference,
          candidate_stdout_sha256,
          candidate_stderr_sha256,
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
      live_prefix = None
      live_timeout_ms = 1000
      normalizations = []
      status = "match"
      compare = ["status", "stdout", "stderr", "tree"]
      allowed_difference = None
      candidate_stdout_sha256 = None
      candidate_stderr_sha256 = None
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
    } else if line.has_prefix("candidate_stderr_sha256 =") {
      candidate_stderr_sha256 = quoted_value(line)
    } else if line.has_prefix("upstream_tests =") {
      upstream_tests = quoted_values(line)
    } else if line.has_prefix("upstream_anchors =") {
      upstream_anchors = quoted_values(line)
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
    Some(expected) => {
      let expected = expected.to_lower()
      expected == current || (expected == "unix" && current != "windows")
    }
  }
}

///|
fn target_environment(
  base : Map[String, String],
  program : @testkit.PreparedProgram,
  architecture : String,
  cpu_count : String,
  wasm_reentry : String,
) -> Map[String, String] {
  let environment = base.copy()
  let platform = runner_platform()
  if platform == "windows" {
    // The isolated fixture environment must retain the platform facts that
    // native just obtains from the Windows process environment/API.
    environment["MOONJUST_OS"] = "windows"
    environment["PROCESSOR_ARCHITECTURE"] = match architecture {
      "X64" | "x64" | "amd64" | "AMD64" => "AMD64"
      "ARM64" | "arm64" => "ARM64"
      "x86" | "X86" => "x86"
      "ARM" | "arm" => "ARM"
      value => value
    }
  }
  if program.is_wrapped() {
    environment["MOONJUST_OS"] = platform
    environment["MOONJUST_ARCH"] = match architecture {
      "X64" | "x64" => "x86_64"
      "ARM64" | "arm64" => "aarch64"
      value => value
    }
    environment["MOONJUST_NUM_CPUS"] = cpu_count
    if !wasm_reentry.is_empty() {
      environment["MOONJUST_EXECUTABLE"] = wasm_reentry
      environment["MOONJUST_WASM_CANDIDATE"] = program.subject()
      environment["MOONJUST_MOONRUN"] = @env.get_env_var("MOONJUST_MOONRUN").unwrap_or(
        "moonrun",
      )
    }
  }
  environment
}

///|
async fn host_architecture() -> String {
  let process = @testkit.run("uname", ["-m"])
  if process.status == 0 {
    let value = @utf8.decode(process.stdout) catch { _ => "" }
    if !value.trim().is_empty() {
      return value.trim().to_owned()
    }
  }
  @env.get_env_var("RUNNER_ARCH").unwrap_or(
    @env.get_env_var("PROCESSOR_ARCHITECTURE").unwrap_or("x86_64"),
  )
}

///|
async fn host_cpu_count() -> String {
  let process = @testkit.run("getconf", ["_NPROCESSORS_ONLN"])
  if process.status == 0 {
    let value = @utf8.decode(process.stdout) catch { _ => "" }
    if !value.trim().is_empty() {
      return value.trim().to_owned()
    }
  }
  @env.get_env_var("NUMBER_OF_PROCESSORS").unwrap_or("1")
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
    let raw_target = fields[1].to_owned()
    let target = if runner_platform() == "windows" &&
      !@path.Path(raw_target).is_absolute() {
      join(root, raw_target)
    } else {
      raw_target
    }
    @fs.symlink(
      join(root, fields[0].to_owned()).view(),
      target=target.view(),
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
  program : @testkit.PreparedProgram,
  case_dir : String,
  root : String,
  cwd : String,
  rules : ArrayView[String],
  architecture : String,
  cpu_count : String,
  wasm_reentry : String,
) -> Array[StepResult] {
  let result : Array[StepResult] = []
  let steps_root = join(case_dir, "steps")
  for name in @fs.readdir(steps_root, include_hidden=false, sort=true) {
    let step_dir = join(steps_root, name)
    guard @fs.kind(step_dir) == Directory else { continue }
    apply_step_changes(step_dir, root)
    let args = arguments(step_dir, root)
    let stdin = read_optional_bytes(join(step_dir, "stdin"))
    let env = target_environment(
      environment(step_dir, root),
      program,
      architecture,
      cpu_count,
      wasm_reentry,
    )
    let execution = @testkit.run_prepared_bytes(
      program,
      args,
      stdin~,
      cwd~,
      extra_env=env,
      inherit_env=false,
    )
    result.push({
      status: execution.status,
      stdout: normalize_output(execution.stdout, root, program.subject(), rules),
      stderr: normalize_output(execution.stderr, root, program.subject(), rules),
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
  if root.is_empty() {
    return bytes
  }
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
fn normalize_snapshot(
  result : CaseResult,
  program : String,
  rules : ArrayView[String],
) -> CaseResult {
  {
    ..result,
    stdout: normalize_output(result.stdout, "", program, rules),
    stderr: normalize_output(result.stderr, "", program, rules),
    merged: result.merged.map(fn(value) {
      normalize_output(value, "", program, rules)
    }),
    steps: result.steps.map(fn(step) {
      {
        status: step.status,
        stdout: normalize_output(step.stdout, "", program, rules),
        stderr: normalize_output(step.stderr, "", program, rules),
      }
    }),
  }
}

///|
/// Apply only fixture-declared, structural normalizations. These rules are
/// intentionally finite and deterministic; all fields not named by a rule
/// remain byte-for-byte comparable.
fn normalize_output(
  bytes : Bytes,
  root : String,
  program : String,
  rules : ArrayView[String],
) -> Bytes {
  let base = normalize(bytes, root)
  let text = @utf8.decode(base) catch { _ => return base }
  let mut result = text
  for rule in rules {
    result = match rule {
      "datetime" => normalize_datetime(result)
      "duration" => normalize_duration(result)
      "timestamp" => normalize_timestamp(result)
      "choose" => normalize_choice(result)
      "uuid" => normalize_uuid(result)
      "parallel-order" => normalize_parallel_order(result)
      "program-path" => normalize_program_path(result)
      "temp-path" => normalize_temp_path(result)
      "module-path" =>
        result.replace_all(old="<CASE_ROOT>/foo.just", new="foo.just")
      _ => result
    }
  }
  // The program path is an execution detail only when explicitly declared by
  // the fixture; this keeps ordinary diagnostics exact.
  if rules.contains("program-path") && !program.is_empty() {
    result = result.replace_all(old=program, new="<JUST>")
  }
  @utf8.encode(result)
}

///|
fn decimal_digit(character : Char) -> Bool {
  character >= '0' && character <= '9'
}

///|
fn decimal_range(text : String, start : Int, length : Int) -> Bool {
  let view = text.view(start_offset=start, end_offset=start + length)
  for character in view {
    if !decimal_digit(character) {
      return false
    }
  }
  true
}

///|
fn normalize_datetime(text : String) -> String {
  guard text.length() >= 10 else { return text }
  guard text[4] == '-' && text[7] == '-' else { return text }
  guard decimal_range(text, 0, 4) &&
    decimal_range(text, 5, 2) &&
    decimal_range(text, 8, 2) else {
    return text
  }
  "<DATE>" + text.view(start_offset=10).to_owned()
}

///|
fn normalize_duration(text : String) -> String {
  guard text.find(" completed in ") is Some(start) else { return text }
  let after = start + " completed in ".length()
  guard text.view(start_offset=after).find("s") is Some(end) else {
    return text
  }
  let end = after + end
  let value = text.view(start_offset=after, end_offset=end)
  guard !value.is_empty() && value.all(fn(c) { decimal_digit(c) || c == '.' }) else {
    return text
  }
  text[:after].to_owned() +
  "<DURATION>" +
  text.view(start_offset=end).to_owned()
}

///|
fn normalize_timestamp(text : String) -> String {
  guard text.has_prefix("[") &&
    text.length() >= 10 &&
    text[3] == ':' &&
    text[6] == ':' &&
    text[9] == ']' &&
    decimal_range(text, 1, 2) &&
    decimal_range(text, 4, 2) &&
    decimal_range(text, 7, 2) else {
    return text
  }
  let end = 9
  "[<TIME>]" + text.view(start_offset=end + 1).to_owned()
}

///|
fn normalize_choice(text : String) -> String {
  let suffix = if text.has_suffix("\n") { "\n" } else { "" }
  let value = if suffix.is_empty() {
    text
  } else {
    text[:text.length() - 1].to_owned()
  }
  if value.length() != 10 ||
    value.contains("\n") ||
    !value.all(fn(c) {
      c == 'x' || c == 'X' || c == 'y' || c == 'Y' || c == 'z' || c == 'Z'
    }) {
    text
  } else {
    "<CHOICE>" + suffix
  }
}

///|
fn normalize_uuid(text : String) -> String {
  let suffix = if text.has_suffix("\n") { "\n" } else { "" }
  let value = if suffix.is_empty() {
    text
  } else {
    text[:text.length() - 1].to_owned()
  }
  guard value.length() == 36 else { return text }
  guard value[8] == '-' &&
    value[13] == '-' &&
    value[18] == '-' &&
    value[23] == '-' else {
    return text
  }
  "<UUID>" + suffix
}

///|
fn normalize_parallel_order(text : String) -> String {
  let ending = text.has_suffix("\n")
  let lines = text.split("\n").collect()
  let values : Array[String] = []
  for index, line in lines {
    if ending && index == lines.length() - 1 {
      continue
    }
    values.push(line.to_owned())
  }
  values.sort()
  values.join("\n") + (if ending { "\n" } else { "" })
}

///|
fn normalize_program_path(text : String) -> String {
  guard text.has_prefix("'") && text.find("'") is Some(first) else {
    return text
  }
  guard text.view(start_offset=first + 1).find("'") is Some(offset) else {
    return text
  }
  let second = first + 1 + offset
  "'<JUST>" + text.view(start_offset=second).to_owned()
}

///|
fn normalize_temp_path(text : String) -> String {
  let text = replace_windows_temp_root(
    text, "C:\\Users\\RUNNER~1\\AppData\\Local\\Temp\\moonjust-compat-official.",
  )
  let text = replace_windows_temp_root(
    text, "C:\\Users\\RUNNER~1\\AppData\\Local\\Temp\\moonjust-compat-candidate.",
  )
  let suffix = if text.has_suffix("\n") { "\n" } else { "" }
  if text.is_empty() || (text.contains("\n") && !text.has_suffix("\n")) {
    text
  } else {
    let value = if suffix.is_empty() {
      text
    } else {
      text[:text.length() - 1].to_owned()
    }
    let parts = value.replace_all(old="\\", new="/").split("/").collect()
    guard parts.length() >= 2 &&
      parts.last() is Some(file) &&
      !file.is_empty() &&
      file.has_suffix(".txt") else {
      return text
    }
    "<TEMP_PATH>/" + file.to_owned() + suffix
  }
}

///|
/// Replace only the generated compatibility root component in Windows paths.
/// The token is intentionally finite and marker-based; no arbitrary wildcard
/// or regular-expression matching is used.
fn replace_windows_temp_root(text : String, marker : String) -> String {
  let output = StringBuilder()
  let mut cursor = 0
  while cursor < text.length() {
    let remaining = text.view(start_offset=cursor)
    guard remaining.find(marker) is Some(offset) else {
      output.write_string(remaining.to_owned())
      break
    }
    let start = cursor + offset
    output.write_string(
      text.view(start_offset=cursor, end_offset=start).to_owned(),
    )
    let token_start = start + marker.length()
    let mut token_end = token_start
    for character in text.view(start_offset=token_start) {
      if character == '\\' ||
        character == '/' ||
        character == '"' ||
        character == '\'' ||
        character == ' ' ||
        character == ']' {
        break
      }
      token_end += 1
    }
    output.write_string("<CASE_ROOT>")
    cursor = token_end
  }
  output.to_string()
}

///|
async fn run_side(
  program : @testkit.PreparedProgram,
  case_dir : String,
  metadata : CaseMetadata,
  side : String,
  architecture : String,
  cpu_count : String,
  wasm_reentry : String,
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
    let steps = run_steps(
      program,
      case_dir,
      root,
      cwd,
      metadata.normalizations,
      architecture,
      cpu_count,
      wasm_reentry,
    )
    let last = steps[steps.length() - 1]
    return {
      status: last.status,
      stdout: normalize_output(
        concatenate_step_stream(steps, true),
        root,
        program.subject(),
        metadata.normalizations,
      ),
      stderr: normalize_output(
        concatenate_step_stream(steps, false),
        root,
        program.subject(),
        metadata.normalizations,
      ),
      merged: None,
      tree: normalize(tree_snapshot(root), root),
      live: true,
      steps,
    }
  }
  let args = arguments(case_dir, root)
  let stdin = read_optional_bytes(join(case_dir, "stdin"))
  let env = target_environment(
    environment(case_dir, root),
    program,
    architecture,
    cpu_count,
    wasm_reentry,
  )
  let (status, stdout, stderr, live) = match metadata.live_prefix {
    Some(prefix) => {
      let result = @testkit.run_live_stdout_prepared(
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
      let result = @testkit.run_prepared_bytes(
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
    let merged_env = target_environment(
      environment(case_dir, merged_root),
      program,
      architecture,
      cpu_count,
      wasm_reentry,
    )
    let result = @testkit.run_merged_prepared(
      program, merged_args, stdin, merged_cwd, merged_env,
    )
    Some(normalize(result.1, merged_root))
  } else {
    None
  }
  {
    status,
    stdout: normalize_output(
      stdout,
      root,
      program.subject(),
      metadata.normalizations,
    ),
    stderr: normalize_output(
      stderr,
      root,
      program.subject(),
      metadata.normalizations,
    ),
    merged,
    tree: normalize(tree_snapshot(root), root),
    live,
    steps: [
      {
        status,
        stdout: normalize_output(
          stdout,
          root,
          program.subject(),
          metadata.normalizations,
        ),
        stderr: normalize_output(
          stderr,
          root,
          program.subject(),
          metadata.normalizations,
        ),
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
    _ => None
  }
  match expected_digest {
    Some((expected, bytes)) =>
      @crypto.bytes_to_hex_string(@crypto.sha256(bytes)) == expected
    None => false
  }
}

///|
async fn official_is_pinned(program : @testkit.PreparedProgram) -> Bool {
  let result = @testkit.run_prepared_bytes(program, ["--version"])
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
async fn candidate_version_matches(
  program : @testkit.PreparedProgram,
  version : String,
) -> Bool {
  let result = @testkit.run_prepared_bytes(program, ["--version"])
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
fn outline_contains_spec(outline : String, spec : SpecCase) -> Bool {
  guard spec.local_test is Some(name) else { return false }
  guard location_parts(spec.fixture) is Some((path, line_number)) else {
    return false
  }
  let segments = path.split("/").collect()
  guard segments.last() is Some(file) else { return false }
  let package_path = segments[:segments.length() - 1].join("/")
  let location = "/" +
    package_path +
    " " +
    file.to_owned() +
    ":" +
    line_number.to_string() +
    " "
  let declaration = " name=\"" + name + "\""
  for line in outline.split("\n") {
    if line.contains(location) && line.has_suffix(declaration) {
      return true
    }
  }
  false
}

///|
async fn execute_moonbit_specs(
  specs : Map[String, SpecCase],
  failures : Array[String],
) -> Set[String] {
  let executed : Set[String] = Set([])
  let test_result = @testkit.run("moon", [
    "test", "--target", "native", "--no-parallelize",
  ])
  if test_result.status != 0 {
    failures.push("MoonBit spec test execution failed")
    return executed
  }
  let outline = @testkit.run("moon", ["test", "--target", "native", "--outline"])
  if outline.status != 0 {
    failures.push("MoonBit spec test outline failed")
    return executed
  }
  let outline_text = @utf8.decode(outline.stdout) catch {
    _ => {
      failures.push("MoonBit spec test outline is not UTF-8")
      return executed
    }
  }
  for upstream_test, spec in specs {
    let fixture_path = spec.fixture
      .split(":")
      .collect()
      .get(0)
      .unwrap_or("")
      .to_owned()
    if !fixture_path.has_suffix("upstream-fixtures.txt") &&
      outline_contains_spec(outline_text, spec) {
      executed.add(upstream_test)
    }
  }
  executed
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
  let execution_target = option(args, "--execution-target").unwrap_or("native")
  let spec_index = parse_spec_index(
    read_text(
      option(args, "--spec-index").unwrap_or(
        "tests/compatibility/upstream/just-1.57.0/spec-index.txt",
      ),
    ),
  )
  let candidate = @testkit.prepare_program(
    candidate_value,
    runner=option(args, "--candidate-runner").unwrap_or(""),
  )
  let official = @testkit.prepare_program(official_value)
  let parsed_manifest = parse_manifest(read_text(manifest))
  let metadata = parsed_manifest.cases
  let upstream_names = upstream_test_names(read_text(upstream_list))
  let mut matched = 0
  let mut known = 0
  let mut product_identity = 0
  let mut selected_found = false
  let fixture_cache : Map[String, String] = Map([])
  let failures : Array[String] = []
  let executed : Set[String] = Set([])
  let exact : Set[String] = Set([])
  let known_upstream : Set[String] = Set([])
  let failed_upstream : Set[String] = Set([])
  let deferred : Set[String] = Set([])
  // MoonBit specs run under `moon test`; this set is populated only by an
  // explicit external execution report, never inferred from the index.
  let spec_executed : Set[String] = if has_flag(args, "--strict-coverage") {
    execute_moonbit_specs(spec_index, failures)
  } else {
    Set([])
  }
  let architecture = host_architecture()
  let cpu_count = host_cpu_count()
  let wasm_reentry = match option(args, "--wasm-reentry") {
    Some(path) if !path.is_empty() => @fs.realpath(path)
    _ => ""
  }
  if execution_target != "native" && execution_target != "wasm" {
    failures.push("execution target must be `native` or `wasm`")
  }
  if execution_target == "wasm" && option(args, "--candidate-runner") is None {
    failures.push("Wasm compatibility requires --candidate-runner")
  }
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
  let manifest_upstream : Set[String] = Set([])
  for
    error in spec_index_shape_errors(
      read_text(
        option(args, "--spec-index").unwrap_or(
          "tests/compatibility/upstream/just-1.57.0/spec-index.txt",
        ),
      ),
    ) {
    failures.push(error)
  }
  for name, details in metadata {
    let case_dir = join(cases_root, name)
    for error in fixture_structure_errors(name, case_dir) {
      failures.push(error)
    }
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
    for rule in details.normalizations {
      if ![
          "datetime", "duration", "timestamp", "choose", "uuid", "parallel-order",
          "program-path", "temp-path", "module-path",
        ].contains(rule) {
        failures.push(name + ": unknown output normalization " + rule)
      }
    }
    if details.status == "expected-difference" &&
      details.allowed_difference is None {
      failures.push(name + ": expected difference has no named reason")
    }
    if details.status == "expected-difference" &&
      details.allowed_difference != Some("product-identity") {
      failures.push(name + ": functional expected differences are forbidden")
    }
    if details.status == "expected-difference" &&
      details.candidate_stdout_sha256 is None &&
      details.candidate_stderr_sha256 is None {
      failures.push(name + ": expected difference has no candidate digest")
    }
    for upstream_test in details.upstream_tests {
      if manifest_upstream.contains(upstream_test) {
        failures.push(
          "duplicate differential upstream identity: " + upstream_test,
        )
      } else {
        manifest_upstream.add(upstream_test)
      }
      if !upstream_names.contains(upstream_test) {
        failures.push(
          name +
          ": upstream anchor is absent from pinned just test list: " +
          upstream_test,
        )
      }
    }
    if details.upstream_tests.length() != details.upstream_anchors.length() {
      failures.push(name + ": upstream test and anchor counts differ")
    } else {
      for index, upstream_test in details.upstream_tests {
        match
          validate_upstream_anchor(
            upstream_test,
            details.upstream_anchors[index],
          ) {
          Some(error) => failures.push(error)
          None => ()
        }
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
    match validate_upstream_anchor(upstream_test, spec.anchor) {
      Some(error) => failures.push(error)
      None => ()
    }
    match validate_spec_anchor(upstream_test, spec) {
      Some(error) => failures.push(error)
      None => ()
    }
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
        upstream_anchors: [],
        normalizations: [],
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
      for upstream_test in details.upstream_tests {
        deferred.add(upstream_test)
      }
      @stdio.stdout.write(
        "SKIP  " + name + " (platform=" + details.platform.unwrap_or("") + ")\n",
      )
      continue
    }
    let stdout_regex = @fs.exists(join(case_dir, "stdout.regex"))
    let stderr_regex = @fs.exists(join(case_dir, "stderr.regex"))
    if stdout_regex || stderr_regex {
      failures.push(
        name + ": regex expectations are forbidden; use exact bytes",
      )
      for upstream_test in details.upstream_tests {
        failed_upstream.add(upstream_test)
      }
      continue
    }
    let official_result = run_side(
      official, case_dir, details, "official", architecture, cpu_count, "",
    )
    for upstream_test in details.upstream_tests {
      executed.add(upstream_test)
    }
    if record_expected {
      write_expected(case_dir, official_result)
    }
    let expected_snapshot_result = expected_snapshot(case_dir).map(fn(
      snapshot,
    ) {
      normalize_snapshot(snapshot, official.subject(), details.normalizations)
    })
    match expected_snapshot_result {
      Some(snapshot) if verify_snapshots && !record_expected => {
        let snapshot_differences = difference_fields(
          snapshot, official_result, details,
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
    let actual = run_side(
      candidate, case_dir, details, "candidate", architecture, cpu_count, wasm_reentry,
    )
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
      for upstream_test in details.upstream_tests {
        exact.add(upstream_test)
      }
      @stdio.stdout.write("PASS  " + name + "\n")
    } else if expectation == "difference" &&
      expected_difference_allowed(
        details.allowed_difference,
        differences,
        actual,
        details,
      ) {
      if details.allowed_difference == Some("product-identity") {
        product_identity += 1
      } else {
        known += 1
        for upstream_test in details.upstream_tests {
          known_upstream.add(upstream_test)
        }
      }
      @stdio.stdout.write(
        "XDIFF " + name + " [" + differences.join(", ") + "]\n",
      )
    } else {
      write_difference_details(name, differences, expected, actual)
      for upstream_test in details.upstream_tests {
        failed_upstream.add(upstream_test)
      }
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
  let mut differential_declared = 0
  let mut differential_executed = 0
  let mut differential_exact = 0
  let mut differential_known = 0
  let mut spec_declared = 0
  let mut spec_done = 0
  let mut completion = 0
  let mut signal = 0
  let mut unclassified = 0
  let mut deferred_count = 0
  for upstream_test in upstream_names {
    let (status, _, _, _) = coverage_status(upstream_test, metadata, spec_index)
    match status {
      "differential-exact" | "differential-known-difference" => {
        differential_declared += 1
        if executed.contains(upstream_test) {
          differential_executed += 1
        }
        if exact.contains(upstream_test) {
          differential_exact += 1
        }
        if known_upstream.contains(upstream_test) {
          differential_known += 1
        }
      }
      "moonbit-spec-exact" => {
        spec_declared += 1
        if spec_executed.contains(upstream_test) {
          spec_done += 1
        }
      }
      "excluded-completion" => completion += 1
      "excluded-signal" => signal += 1
      _ => unclassified += 1
    }
    if deferred.contains(upstream_test) {
      deferred_count += 1
    }
  }
  let coverage_incomplete = upstream_names.length() !=
    differential_executed + spec_done + completion + signal + deferred_count ||
    differential_known != 0 ||
    (deferred_count != 0 && !has_flag(args, "--allow-deferred-platform")) ||
    unclassified != 0 ||
    spec_done != spec_declared
  match coverage_report {
    Some(path) =>
      @fs.write_file(
        path,
        @utf8.encode(
          coverage_json(
            upstream_names,
            metadata,
            spec_index,
            executed,
            exact,
            known_upstream,
            failed_upstream,
            deferred,
            spec_executed,
            failures.length() + (if coverage_incomplete { 1 } else { 0 }),
            runner_platform(),
            execution_target,
          ),
        ),
      )
    None => ()
  }
  for failure in failures {
    @stdio.stderr.write("FAIL  " + failure + "\n")
  }
  @stdio.stdout.write(
    "matched=" +
    matched.to_string() +
    " known_differences=" +
    known.to_string() +
    " product_identity_difference=" +
    product_identity.to_string() +
    " failures=" +
    failures.length().to_string() +
    " version=" +
    (if failures.is_empty() { "pass" } else { "fail" }) +
    " upstream_total=" +
    upstream_names.length().to_string() +
    " differential_declared=" +
    differential_declared.to_string() +
    " differential_executed=" +
    differential_executed.to_string() +
    " differential_exact=" +
    differential_exact.to_string() +
    " differential_known_difference=" +
    differential_known.to_string() +
    " moonbit_spec_declared=" +
    spec_declared.to_string() +
    " moonbit_spec_executed=" +
    spec_done.to_string() +
    " excluded_completion=" +
    completion.to_string() +
    " excluded_signal=" +
    signal.to_string() +
    " deferred_platform=" +
    deferred_count.to_string() +
    " unclassified=" +
    unclassified.to_string() +
    "\n",
  )
  if has_flag(args, "--strict-coverage") && coverage_incomplete {
    @stdio.stderr.write("FAIL  upstream coverage is incomplete\n")
    @sys.exit(1)
  }
  if !failures.is_empty() {
    @sys.exit(1)
  }
}
