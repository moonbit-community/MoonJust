///|
async fn run_workload(
  program : @testkit.PreparedProgram,
  fixture : Fixture,
  command : Array[String],
) -> @testkit.RunResult {
  match fixture.stdin_path {
    Some(path) =>
      @testkit.run_prepared(
        program,
        command,
        stdin_path=path,
        cwd=fixture.directory,
      )
    None => @testkit.run_prepared(program, command, cwd=fixture.directory)
  }
}

///|
async fn sample(
  program : @testkit.PreparedProgram,
  fixture : Fixture,
  workload : Workload,
) -> Int64 {
  let started = @async.now()
  let result = run_workload(program, fixture, workload.command)
  if result.status != 0 {
    @stdio.stderr.write("benchmark command failed: " + workload.name + "\n")
    @sys.exit(1)
  }
  @async.now() - started
}

///|
async fn behavior_matches(
  candidate : @testkit.PreparedProgram,
  official : @testkit.PreparedProgram,
  fixture : Fixture,
  workload : Workload,
) -> Bool {
  let actual = run_workload(candidate, fixture, workload.command)
  if workload.name == "startup-version" {
    return actual.status == 0
  }
  let expected = run_workload(official, fixture, workload.command)
  actual.status == expected.status &&
  @testkit.bytes_equal(actual.stdout, expected.stdout) &&
  @testkit.bytes_equal(actual.stderr, expected.stderr)
}

///|
async fn warmup(
  candidate : @testkit.PreparedProgram,
  official : @testkit.PreparedProgram,
  fixture : Fixture,
  workload : Workload,
  count : Int,
) -> Unit {
  for _ in 0..<count {
    ignore(sample(candidate, fixture, workload))
    ignore(sample(official, fixture, workload))
  }
}

///|
async fn measure(
  candidate : @testkit.PreparedProgram,
  official : @testkit.PreparedProgram,
  fixture : Fixture,
  workload : Workload,
  settings : BenchmarkSettings,
) -> Measurements {
  let behavior_started = @async.now()
  let behavior_ok = behavior_matches(candidate, official, fixture, workload)
  let behavior_ms = @async.now() - behavior_started
  if !behavior_ok {
    @stdio.stderr.write(
      "benchmark workload behavior differs from official: " +
      workload.name +
      "\n",
    )
    @sys.exit(1)
  }
  // Profiles do not use warmups. The custom option remains available when
  // investigating a local measurement problem.
  warmup(candidate, official, fixture, workload, settings.warmups)
  let candidate_samples : Array[Int64] = []
  let official_samples : Array[Int64] = []
  let batch_ratios : Array[Double] = []
  for _ in 0..<settings.batches {
    let batch_candidate : Array[Int64] = []
    let batch_official : Array[Int64] = []
    for index = 0; index < settings.rounds; index = index + 1 {
      if index % 2 == 0 {
        let candidate_time = sample(candidate, fixture, workload)
        let official_time = sample(official, fixture, workload)
        candidate_samples.push(candidate_time)
        official_samples.push(official_time)
        batch_candidate.push(candidate_time)
        batch_official.push(official_time)
      } else {
        let official_time = sample(official, fixture, workload)
        let candidate_time = sample(candidate, fixture, workload)
        official_samples.push(official_time)
        candidate_samples.push(candidate_time)
        batch_candidate.push(candidate_time)
        batch_official.push(official_time)
      }
    }
    batch_ratios.push(ratio(median(batch_candidate), median(batch_official)))
  }
  {
    candidate: candidate_samples,
    official: official_samples,
    batch_ratios,
    behavior_ms,
  }
}

///|
async fn calibrate_noops(official : @testkit.PreparedProgram) -> Workload? {
  for size in [1, 2, 4, 8, 16, 32, 64, 128, 256] {
    let provisional = noops_workload(size, 0L)
    let fixture = prepare_fixture(provisional)
    let started = @async.now()
    let result = run_workload(official, fixture, provisional.command)
    let elapsed = @async.now() - started
    remove_fixture(fixture)
    if result.status != 0 {
      return None
    }
    if elapsed >= 32L && elapsed <= 500L {
      return Some(noops_workload(size, elapsed))
    }
  }
  None
}
