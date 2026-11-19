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
  inputs : ArrayView[String],
  platform : String,
) -> Map[String, String] {
  let environment = base.copy()
  if platform == "windows" && !architecture.is_empty() {
    // The isolated fixture environment must retain the platform facts that
    // native just obtains from the Windows process environment/API.
    environment["PROCESSOR_ARCHITECTURE"] = match architecture {
      "X64" | "x64" | "x86_64" | "amd64" | "AMD64" => "AMD64"
      "ARM64" | "arm64" => "ARM64"
      "x86" | "X86" => "x86"
      "ARM" | "arm" => "ARM"
      value => value
    }
  }
  if program.is_wrapped() {
    if inputs.contains("MOONJUST_ARCH") && !architecture.is_empty() {
      environment["MOONJUST_ARCH"] = match architecture {
        "X64" | "x64" | "AMD64" | "amd64" => "x86_64"
        "ARM64" | "arm64" => "aarch64"
        value => value
      }
    }
    if inputs.contains("MOONJUST_NUM_CPUS") && !cpu_count.is_empty() {
      environment["MOONJUST_NUM_CPUS"] = cpu_count
    }
    if inputs.contains("MOONJUST_EXECUTABLE") && !wasm_reentry.is_empty() {
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
async fn unix_host_fact(program : String, argument : String) -> String {
  let result = @testkit.run(program, [argument]) catch { _ => return "" }
  guard result.status == 0 else { return "" }
  let text = @utf8.decode(result.stdout) catch { _ => return "" }
  text.trim().to_owned()
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
  inputs : ArrayView[String],
  platform : String,
) -> Array[StepResult] {
  let result : Array[StepResult] = []
  let steps_root = join(case_dir, "steps")
  for name in @fs.readdir(steps_root, include_hidden=false, sort=true) {
    let step_dir = join(steps_root, name)
    guard @fs.kind(step_dir) == Directory else { continue }
    apply_step_changes(step_dir, root, platform)
    let args = arguments(step_dir, root)
    let stdin = read_optional_bytes(join(step_dir, "stdin"))
    let env = target_environment(
      environment(step_dir, root),
      program,
      architecture,
      cpu_count,
      wasm_reentry,
      inputs,
      platform,
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
      stdout: normalize_output(
        execution.stdout,
        root,
        program.subject(),
        rules,
        stdout=true,
      ),
      stderr: normalize_output(execution.stderr, root, program.subject(), rules),
    })
  }
  result
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
  platform : String,
  initial_tree? : Ref[Bytes],
) -> CaseResult {
  let root = @fs.tmpdir(prefix="moonjust-compat-" + side)
  defer (@fs.remove(root, recursive=true) catch { _ => () })
  defer (@fs.remove(link_metadata_path(root)[:]) catch { _ => () })
  prepare_root(case_dir, root, metadata.cwd, platform)
  if initial_tree is Some(tree) {
    tree.val = normalize(tree_snapshot(root), root)
  }
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
      metadata.host_inputs,
      platform,
    )
    let last = steps[steps.length() - 1]
    return {
      status: last.status,
      stdout: normalize_output(
        concatenate_step_stream(steps, true),
        root,
        program.subject(),
        metadata.normalizations,
        stdout=true,
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
    metadata.host_inputs,
    platform,
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
    defer (@fs.remove(merged_root, recursive=true) catch { _ => () })
    prepare_root(case_dir, merged_root, metadata.cwd, platform)
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
      metadata.host_inputs,
      platform,
    )
    let result = @testkit.run_merged_prepared(
      program, merged_args, stdin, merged_cwd, merged_env,
    )
    Some(normalize(result.1, merged_root))
  } else {
    None
  }
  let step : StepResult = {
    status,
    stdout: normalize_output(
      stdout,
      root,
      program.subject(),
      metadata.normalizations,
      stdout=true,
    ),
    stderr: normalize_output(
      stderr,
      root,
      program.subject(),
      metadata.normalizations,
    ),
  }
  {
    status,
    stdout: step.stdout,
    stderr: step.stderr,
    merged,
    tree: normalize(tree_snapshot(root), root),
    live,
    steps: [step],
  }
}

///|
async fn official_is_pinned(program : @testkit.PreparedProgram) -> Bool {
  let result = @testkit.run_prepared_bytes(program, ["--version"])
  result.status == 0 &&
  @testkit.bytes_equal(result.stdout, b"just 1.59.0\n") &&
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
