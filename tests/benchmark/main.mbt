///|
priv struct Program {
  executable : String
  prefix : Array[String]
}

///|
priv struct Workload {
  name : String
  size : Int
  source : String
  command : Array[String]
}

///|
fn option(args : ArrayView[String], name : String, fallback : String) -> String {
  for index, value in args {
    if value == name && index + 1 < args.length() {
      return args[index + 1]
    }
  }
  fallback
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
async fn program(
  args : ArrayView[String],
  path_option : String,
  runner_option : String,
) -> Program {
  let path = option(args, path_option, "")
  let path = if path.contains("/") || path.contains("\\") {
    @fs.realpath(path)
  } else {
    path
  }
  let runner = option(args, runner_option, "")
  if runner.is_empty() {
    { executable: path, prefix: [], }
  } else if runner.contains("moonrun") {
    // moonrun consumes the wasm path first; `--` is its argument boundary.
    { executable: runner, prefix: [path, "--"], }
  } else {
    { executable: runner, prefix: [path], }
  }
}

///|
fn program_arguments(
  program : Program,
  args : ArrayView[String],
) -> Array[String] {
  let result = program.prefix.copy()
  for argument in args {
    result.push(argument)
  }
  result
}

///|
fn recipe_names(size : Int) -> Array[String] {
  let names : Array[String] = []
  for index = 0; index < size; index = index + 1 {
    names.push("r" + index.to_string())
  }
  names
}

///|
fn recipe_lines(names : ArrayView[String], body : String) -> Array[String] {
  let lines : Array[String] = []
  for name in names {
    lines.push(name + ":\n    @" + body)
  }
  lines
}

///|
fn generated_source(kind : String, size : Int) -> String {
  let names = recipe_names(size)
  match kind {
    "dag" => {
      let lines : Array[String] = []
      lines.push("root: " + names.join(" ") + "\n    @:")
      for line in recipe_lines(names, ":") {
        lines.push(line)
      }
      lines.join("\n") + "\n"
    }
    "modules" =>
      "set dotenv-load := true\n" +
      "name := env_var('NAME')\n" +
      "root: " +
      names.join(" ") +
      "\n    @: echo {{name}}\n" +
      recipe_lines(names, ":").join("\n") +
      "\n"
    "scripts" => {
      let lines : Array[String] = []
      lines.push("root: " + names.join(" ") + "\n    @:")
      for index, name in names {
        if index % 3 == 0 {
          lines.push(name + ":\n    #!/bin/sh\n    echo script")
        } else if index % 3 == 1 {
          lines.push(name + ":\n    @:")
        } else {
          lines.push(name + ":\n    @echo line")
        }
      }
      lines.join("\n") + "\n"
    }
    _ => {
      let lines : Array[String] = []
      lines.push("root: " + names.join(" ") + "\n    @:")
      for line in recipe_lines(names, ":") {
        lines.push(line)
      }
      lines.join("\n") + "\n"
    }
  }
}

///|
fn workload(
  name : String,
  size : Int,
  kind : String,
  command : Array[String],
) -> Workload {
  {
    name,
    size,
    source: if kind == "startup" {
      ""
    } else {
      generated_source(kind, size)
    },
    command,
  }
}

///|
fn workloads(justfile : String) -> Array[Workload] {
  [
    workload("startup-version", 1, "startup", ["--version"]),
    workload("check-1000", 1000, "recipes", [
      "--justfile", justfile, "--fmt", "--check",
    ]),
    workload("check-5000", 5000, "recipes", [
      "--justfile", justfile, "--fmt", "--check",
    ]),
    workload("format-1000", 1000, "recipes", [
      "--justfile", justfile, "--fmt", "--check",
    ]),
    workload("summary-1000", 1000, "recipes", [
      "--justfile", justfile, "--summary",
    ]),
    workload("dry-run-dag-256", 256, "dag", [
      "--justfile", justfile, "--dry-run", "root",
    ]),
    workload("dry-run-dag-1000", 1000, "dag", [
      "--justfile", justfile, "--dry-run", "root",
    ]),
    workload("run-noops-64", 64, "recipes", ["--justfile", justfile, "root"]),
    workload("run-noops-256", 256, "recipes", ["--justfile", justfile, "root"]),
    workload("modules-dotenv", 128, "modules", [
      "--justfile", justfile, "--dry-run", "root",
    ]),
    workload("script-recipes", 96, "scripts", [
      "--justfile", justfile, "--dry-run", "root",
    ]),
    workload("stdin-file", 512, "recipes", [
      "--justfile", justfile, "--dry-run", "r0",
    ]),
    workload("wasm-host-check", 2048, "recipes", [
      "--justfile", justfile, "--fmt", "--check",
    ]),
  ]
}

///|
fn median(values : Array[Int64]) -> Int64 {
  values.sort()
  values[values.length() / 2]
}

///|
fn median_double(values : Array[Double]) -> Double {
  values.sort()
  values[values.length() / 2]
}

///|
fn p95(values : Array[Int64]) -> Int64 {
  values.sort()
  let index = (values.length() * 95 + 99) / 100 - 1
  values[index.max(0).min(values.length() - 1)]
}

///|
fn ratio(candidate : Int64, official : Int64) -> Double {
  if official == 0L {
    if candidate == 0L {
      1.0
    } else {
      99.0
    }
  } else {
    candidate.to_double() / official.to_double()
  }
}

///|
fn ratio_ci(
  candidate : Array[Int64],
  official : Array[Int64],
) -> (Double, Double) {
  let ratios : Array[Double] = []
  let count = candidate.length().min(official.length())
  for index = 0; index < count; index = index + 1 {
    ratios.push(ratio(candidate[index], official[index]))
  }
  if ratios.is_empty() {
    return (0.0, 0.0)
  }
  ratios.sort()
  let low = (ratios.length().to_double() * 0.025)
    .to_int()
    .max(0)
    .min(ratios.length() - 1)
  let high = (ratios.length().to_double() * 0.975)
    .to_int()
    .max(0)
    .min(ratios.length() - 1)
  (ratios[low], ratios[high])
}

///|
async fn sample(program : Program, cwd : String, args : Array[String]) -> Int64 {
  let started = @async.now()
  let result = @testkit.run(
    program.executable,
    program_arguments(program, args),
    cwd~,
  )
  if result.status != 0 {
    @stdio.stderr.write("benchmark command failed\n")
    @sys.exit(1)
  }
  @async.now() - started
}

///|
async fn behavior_matches(
  candidate : Program,
  official : Program,
  cwd : String,
  args : Array[String],
) -> Bool {
  let actual = @testkit.run(
    candidate.executable,
    program_arguments(candidate, args),
    cwd~,
  )
  let expected = @testkit.run(
    official.executable,
    program_arguments(official, args),
    cwd~,
  )
  actual.status == expected.status &&
  @testkit.bytes_equal(actual.stdout, expected.stdout) &&
  @testkit.bytes_equal(actual.stderr, expected.stderr)
}

///|
fn json_string(value : String) -> String {
  "\"" +
  value.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"") +
  "\""
}

///|
async fn toolchain_versions() -> (String, String, String) {
  let result = @testkit.run("moon", ["version", "--all"])
  let text = @utf8.decode(result.stdout) catch { _ => "" }
  let mut moon = "unknown"
  let mut moonc = "unknown"
  let mut moonrun = "unknown"
  for line in text.split("\n") {
    let value = line.trim().to_owned()
    if value.has_prefix("moon ") {
      moon = value
    } else if value.has_prefix("moonc ") {
      moonc = value
    } else if value.has_prefix("moonrun ") {
      moonrun = value
    }
  }
  (moon, moonc, moonrun)
}

///|
fn report_json(
  workload : Workload,
  target : String,
  candidate : Array[Int64],
  official : Array[Int64],
  batch_ratios : Array[Double],
  warmups : Int,
  batches : Int,
  rounds : Int,
) -> String {
  let candidate_median = median(candidate.copy())
  let official_median = median(official.copy())
  let candidate_p95 = p95(candidate.copy())
  let official_p95 = p95(official.copy())
  let median_ratio = ratio(candidate_median, official_median)
  let p95_ratio = ratio(candidate_p95, official_p95)
  let (ci_low, ci_high) = ratio_ci(candidate, official)
  "{" +
  "\"target\":" +
  json_string(target) +
  ",\"workload\":" +
  json_string(workload.name) +
  ",\"workload_size\":" +
  workload.size.to_string() +
  ",\"warmups\":" +
  warmups.to_string() +
  ",\"batches\":" +
  batches.to_string() +
  ",\"samples_per_batch\":" +
  rounds.to_string() +
  ",\"candidate_samples\":" +
  candidate.length().to_string() +
  ",\"official_samples\":" +
  official.length().to_string() +
  ",\"candidate_median_ms\":" +
  candidate_median.to_string() +
  ",\"official_median_ms\":" +
  official_median.to_string() +
  ",\"candidate_p95_ms\":" +
  candidate_p95.to_string() +
  ",\"official_p95_ms\":" +
  official_p95.to_string() +
  ",\"median_ratio\":" +
  median_ratio.to_string() +
  ",\"batch_ratio_median\":" +
  median_double(batch_ratios.copy()).to_string() +
  ",\"p95_ratio\":" +
  p95_ratio.to_string() +
  ",\"ci95_low\":" +
  ci_low.to_string() +
  ",\"ci95_high\":" +
  ci_high.to_string() +
  ",\"sample_complete\":true}"
}

///|
fn exceeds_gate(
  target : String,
  name : String,
  median_ratio : Double,
  p95_ratio : Double,
) -> Bool {
  let median_limit = if target == "wasm" { 3.0 } else { 1.10 }
  let p95_limit = if target == "wasm" {
    if name == "startup-version" {
      2.0
    } else {
      3.0
    }
  } else {
    1.25
  }
  median_ratio > median_limit || p95_ratio > p95_limit
}

///|
async fn main {
  let args = @env.args()[1:]
  let candidate = program(args, "--candidate", "--candidate-runner")
  let official = program(args, "--official", "--official-runner")
  let rounds = @string.parse_int(option(args, "--rounds", "15")[:]) catch {
    _ => 0
  }
  let batches = @string.parse_int(option(args, "--batches", "3")[:]) catch {
    _ => 0
  }
  let warmups = @string.parse_int(option(args, "--warmups", "2")[:]) catch {
    _ => 0
  }
  let target = option(args, "--target", "native")
  let output_path = option(args, "--output", "")
  guard !candidate.executable.is_empty() &&
    !official.executable.is_empty() &&
    rounds > 0 &&
    batches > 0 &&
    warmups >= 0 else {
    @stdio.stderr.write(
      "Usage: moonjust-benchmark --candidate PATH --official PATH [--candidate-runner PATH] [--official-runner PATH] [--target native|wasm] [--batches N] [--rounds N] [--warmups N] [--output PATH] [--enforce]\n",
    )
    @sys.exit(2)
    return
  }
  let root = @fs.tmpdir(prefix="moonjust-benchmark")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let (moon_version, moonc_version, moonrun_version) = toolchain_versions()
  let justfile_path = @path.Path(root).join(Path("justfile")).to_string()
  let all = workloads("justfile")
  let reports : Array[String] = []
  let mut gate_failed = false
  for workload in all {
    if !workload.source.is_empty() {
      @fs.write_file(justfile_path, @utf8.encode(workload.source))
    }
    if workload.name == "modules-dotenv" {
      @fs.write_file(
        @path.Path(root).join(Path(".env")).to_string(),
        @utf8.encode("NAME=moonjust\n"),
      )
    }
    let behavior_ok = if workload.name == "startup-version" {
      let actual = @testkit.run(
        candidate.executable,
        program_arguments(candidate, workload.command),
        cwd=root,
      )
      actual.status == 0
    } else {
      behavior_matches(candidate, official, root, workload.command)
    }
    if !behavior_ok {
      @stdio.stderr.write(
        "benchmark workload behavior differs from official: " +
        workload.name +
        "\n",
      )
      @sys.exit(1)
    }
    for _ in 0..<warmups {
      let _ = sample(candidate, root, workload.command)
      let _ = sample(official, root, workload.command)
    }
    let candidate_samples : Array[Int64] = []
    let official_samples : Array[Int64] = []
    let batch_ratios : Array[Double] = []
    for _ in 0..<batches {
      let batch_candidate : Array[Int64] = []
      let batch_official : Array[Int64] = []
      for index = 0; index < rounds; index = index + 1 {
        if index % 2 == 0 {
          let candidate_time = sample(candidate, root, workload.command)
          let official_time = sample(official, root, workload.command)
          candidate_samples.push(candidate_time)
          official_samples.push(official_time)
          batch_candidate.push(candidate_time)
          batch_official.push(official_time)
        } else {
          let official_time = sample(official, root, workload.command)
          let candidate_time = sample(candidate, root, workload.command)
          official_samples.push(official_time)
          candidate_samples.push(candidate_time)
          batch_candidate.push(candidate_time)
          batch_official.push(official_time)
        }
      }
      batch_ratios.push(ratio(median(batch_candidate), median(batch_official)))
    }
    let candidate_p95 = p95(candidate_samples.copy())
    let official_p95 = p95(official_samples.copy())
    let p95_ratio = ratio(candidate_p95, official_p95)
    if has_flag(args, "--enforce") &&
      exceeds_gate(
        target,
        workload.name,
        median_double(batch_ratios.copy()),
        p95_ratio,
      ) {
      gate_failed = true
      @stdio.stderr.write("FAIL  performance gate: " + workload.name + "\n")
    }
    reports.push(
      report_json(
        workload, target, candidate_samples, official_samples, batch_ratios, warmups,
        batches, rounds,
      ),
    )
  }
  let commit = @env.get_env_var("GITHUB_SHA").unwrap_or("unknown")
  let runner_os = @env.get_env_var("RUNNER_OS").unwrap_or("local")
  let runner_arch = @env.get_env_var("RUNNER_ARCH").unwrap_or("unknown")
  let report = "{\"schema_version\":1,\"commit\":" +
    json_string(commit) +
    ",\"official_just_version\":\"1.57.0\"" +
    ",\"moon_version\":" +
    json_string(moon_version) +
    ",\"moonc_version\":" +
    json_string(moonc_version) +
    ",\"moonrun_version\":" +
    json_string(moonrun_version) +
    ",\"runner_os\":" +
    json_string(runner_os) +
    ",\"runner_arch\":" +
    json_string(runner_arch) +
    ",\"target\":" +
    json_string(target) +
    ",\"thresholds\":{\"native_median\":1.1,\"native_p95\":1.25,\"wasm_median\":3.0,\"wasm_startup\":2.0}," +
    "\"workloads\":[" +
    reports.join(",") +
    "]}\n"
  if output_path.is_empty() {
    @stdio.stdout.write(report)
  } else {
    @fs.write_file(output_path, @utf8.encode(report))
    @stdio.stdout.write("wrote " + output_path + "\n")
  }
  if gate_failed {
    @sys.exit(1)
  }
}
