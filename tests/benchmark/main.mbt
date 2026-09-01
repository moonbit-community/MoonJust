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
fn has_option(args : ArrayView[String], name : String) -> Bool {
  for index, value in args {
    if value == name && index + 1 < args.length() {
      return true
    }
  }
  false
}

///|
fn parsed_int(args : ArrayView[String], name : String, fallback : Int) -> Int {
  @string.parse_int(option(args, name, fallback.to_string())[:]) catch {
    _ => 0
  }
}

///|
fn settings(args : ArrayView[String]) -> BenchmarkSettings? {
  let requested = option(args, "--profile", "smoke")
  let custom = has_option(args, "--batches") ||
    has_option(args, "--rounds") ||
    has_option(args, "--warmups")
  let defaults = match requested {
    "smoke" => (1, 5, 0)
    "full" => (3, 15, 0)
    _ => return None
  }
  let profile = if custom { "custom" } else { requested }
  let batches = parsed_int(args, "--batches", defaults.0)
  let rounds = parsed_int(args, "--rounds", defaults.1)
  let warmups = parsed_int(args, "--warmups", defaults.2)
  guard batches > 0 && rounds > 0 && warmups >= 0 else { return None }
  Some({
    profile,
    batches,
    rounds,
    warmups,
    target: option(args, "--target", "native"),
    output_path: option(args, "--output", ""),
    enforce: has_flag(args, "--enforce"),
  })
}

///|
async fn benchmark_program(
  args : ArrayView[String],
  path_option : String,
  runner_option : String,
) -> @testkit.PreparedProgram {
  @testkit.prepare_program(
    option(args, path_option, ""),
    runner=option(args, runner_option, ""),
  )
}

///|
fn usage() -> String {
  "Usage: moonjust-benchmark --candidate PATH --official PATH " +
  "[--candidate-runner PATH] [--official-runner PATH] " +
  "[--target native|wasm] [--profile smoke|full] " +
  "[--batches N] [--rounds N] [--warmups N] [--output PATH] [--enforce]\n"
}

///|
async fn main {
  let args = @env.args()[1:]
  let configuration = settings(args)
  let candidate_path = option(args, "--candidate", "")
  let official_path = option(args, "--official", "")
  guard !candidate_path.is_empty() &&
    !official_path.is_empty() &&
    configuration is Some(settings) else {
    @stdio.stderr.write(usage())
    @sys.exit(2)
    return
  }
  let prepared_at = @async.now()
  let candidate = benchmark_program(args, "--candidate", "--candidate-runner")
  let official = benchmark_program(args, "--official", "--official-runner")
  let runner_prepare_ms = @async.now() - prepared_at
  let (moon_version, moonc_version, moonrun_version) = toolchain_versions()
  let all = workloads()
  match calibrate_noops(official) {
    Some(noops) => all.push(noops)
    None => {
      @stdio.stderr.write(
        "benchmark could not calibrate run-noops to the 32ms-500ms target\n",
      )
      @sys.exit(1)
    }
  }
  let reports : Array[String] = []
  let mut gate_failed = false
  for workload in all {
    let fixture = prepare_fixture(workload)
    let measurements = measure(candidate, official, fixture, workload, settings)
    let candidate_p95 = p95(measurements.candidate.copy())
    let official_p95 = p95(measurements.official.copy())
    if settings.enforce &&
      exceeds_gate(
        settings.target,
        workload.name,
        median_double(measurements.batch_ratios.copy()),
        ratio(candidate_p95, official_p95),
      ) {
      gate_failed = true
      @stdio.stderr.write("FAIL  performance gate: " + workload.name + "\n")
    }
    reports.push(
      workload_report_json(workload, fixture, measurements, settings),
    )
    remove_fixture(fixture)
  }
  let report = report_json(
    settings, reports, runner_prepare_ms, moon_version, moonc_version, moonrun_version,
  )
  if settings.output_path.is_empty() {
    @stdio.stdout.write(report)
  } else {
    @fs.write_file(settings.output_path, @utf8.encode(report))
    @stdio.stdout.write("wrote " + settings.output_path + "\n")
  }
  if gate_failed {
    @sys.exit(1)
  }
}
