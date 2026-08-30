///|
priv struct Program {
  executable : String
  prefix : Array[String]
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
fn median(values : Array[Int64]) -> Int64 {
  values.sort()
  values[values.length() / 2]
}

///|
fn p95(values : Array[Int64]) -> Int64 {
  values.sort()
  let index = (values.length() * 95 + 99) / 100 - 1
  values[index]
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
async fn main {
  let args = @env.args()[1:]
  let candidate = program(args, "--candidate", "--candidate-runner")
  let official = program(args, "--official", "--official-runner")
  let rounds = @string.parse_int(option(args, "--rounds", "15")[:]) catch {
    _ => 0
  }
  guard !candidate.executable.is_empty() &&
    !official.executable.is_empty() &&
    rounds > 0 else {
    @stdio.stderr.write(
      "Usage: moonjust-benchmark --candidate PATH --official PATH " +
      "[--candidate-runner PATH] [--official-runner PATH] [--rounds N]\n",
    )
    @sys.exit(2)
    return
  }
  let root = @fs.tmpdir(prefix="moonjust-benchmark")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let justfile = @path.Path(root).join(Path("justfile")).to_string()
  @fs.write_file(justfile, @utf8.encode("noop:\n  @echo ok\n"))
  let command = ["--justfile", justfile, "--dry-run", "noop"]
  if !behavior_matches(candidate, official, root, command) {
    @stdio.stderr.write("benchmark workload behavior differs from official\n")
    @sys.exit(1)
    return
  }
  let candidate_samples : Array[Int64] = []
  let official_samples : Array[Int64] = []
  for index = 0; index < rounds; index = index + 1 {
    if index % 2 == 0 {
      candidate_samples.push(sample(candidate, root, command))
      official_samples.push(sample(official, root, command))
    } else {
      official_samples.push(sample(official, root, command))
      candidate_samples.push(sample(candidate, root, command))
    }
  }
  let candidate_median = median(candidate_samples.copy())
  let official_median = median(official_samples.copy())
  let candidate_p95 = p95(candidate_samples)
  let official_p95 = p95(official_samples)
  let ratio = if official_median == 0L {
    0.0
  } else {
    candidate_median.to_double() / official_median.to_double()
  }
  let p95_ratio = if official_p95 == 0L {
    0.0
  } else {
    candidate_p95.to_double() / official_p95.to_double()
  }
  @stdio.stdout.write(
    "{\"candidate_median_ms\":" +
    candidate_median.to_string() +
    ",\"official_median_ms\":" +
    official_median.to_string() +
    ",\"candidate_p95_ms\":" +
    candidate_p95.to_string() +
    ",\"official_p95_ms\":" +
    official_p95.to_string() +
    ",\"ratio\":" +
    ratio.to_string() +
    ",\"p95_ratio\":" +
    p95_ratio.to_string() +
    ",\"samples\":" +
    rounds.to_string() +
    "}\n",
  )
}
