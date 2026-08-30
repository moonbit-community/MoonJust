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
fn median(values : Array[Int64]) -> Int64 {
  values.sort()
  values[values.length() / 2]
}

///|
async fn sample(binary : String, cwd : String, args : Array[String]) -> Int64 {
  let started = @async.now()
  let result = @testkit.run(binary, args, cwd~)
  if result.status != 0 {
    @stdio.stderr.write("benchmark command failed\n")
    @sys.exit(1)
  }
  @async.now() - started
}

///|
async fn main {
  let args = @env.args()[1:]
  let candidate = option(args, "--candidate", "")
  let official = option(args, "--official", "")
  let rounds = @string.parse_int(option(args, "--rounds", "15")[:]) catch {
    _ => 0
  }
  guard !candidate.is_empty() && !official.is_empty() && rounds > 0 else {
    @stdio.stderr.write(
      "Usage: moonjust-benchmark --candidate PATH --official PATH [--rounds N]\n",
    )
    @sys.exit(2)
    return
  }
  let root = @fs.tmpdir(prefix="moonjust-benchmark")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let justfile = @path.Path(root).join(Path("justfile")).to_string()
  @fs.write_file(justfile, @utf8.encode("noop:\n  @echo ok\n"))
  let command = ["--justfile", justfile, "--dry-run", "noop"]
  let candidate_samples : Array[Int64] = []
  let official_samples : Array[Int64] = []
  for index = 0; index < rounds; index = index + 1 {
    candidate_samples.push(sample(candidate, root, command))
    official_samples.push(sample(official, root, command))
  }
  let candidate_median = median(candidate_samples)
  let official_median = median(official_samples)
  let ratio = if official_median == 0L {
    0.0
  } else {
    candidate_median.to_double() / official_median.to_double()
  }
  @stdio.stdout.write(
    "{\"candidate_median_ns\":" +
    candidate_median.to_string() +
    ",\"official_median_ns\":" +
    official_median.to_string() +
    ",\"ratio\":" +
    ratio.to_string() +
    ",\"samples\":" +
    rounds.to_string() +
    "}\n",
  )
}
