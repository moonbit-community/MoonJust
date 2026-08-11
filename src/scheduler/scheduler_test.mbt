///|
test "bounded waves preserve serial fences and stable fairness" {
  let tasks = [
    @scheduler.TaskSpec::new(0, 0),
    @scheduler.TaskSpec::new(1, 1),
    @scheduler.TaskSpec::new(2, 2, dependencies=[0]),
    @scheduler.TaskSpec::new(3, 3, dependencies=[1]),
    @scheduler.TaskSpec::new(4, 4, dependencies=[2, 3]),
  ]
  let schedule = @scheduler.build_schedule(tasks, 2)
  assert_eq(schedule.waves(), [[0, 1], [2, 3], [4]])
  assert_eq(schedule.peak(), 2)
  assert_eq(@scheduler.deterministic_failure(schedule, [3, 2]), Some(2))
}

///|
test "invalid jobs dependencies and cycles are typed" {
  try @scheduler.build_schedule([], 0) catch {
    InvalidJobs(0) => ()
    error => fail("unexpected jobs error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid jobs")
  }
  try
    @scheduler.build_schedule(
      [@scheduler.TaskSpec::new(0, 0, dependencies=[1])],
      1,
    )
  catch {
    UnknownDependency(task=0, dependency=1) => ()
    error => fail("unexpected dependency error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unknown dependency")
  }
  try
    @scheduler.build_schedule(
      [
        @scheduler.TaskSpec::new(0, 0, dependencies=[1]),
        @scheduler.TaskSpec::new(1, 1, dependencies=[0]),
      ],
      1,
    )
  catch {
    DependencyCycle([0, 1]) => ()
    error => fail("unexpected cycle error: \{Repr(error)}")
  } noraise {
    _ => fail("expected dependency cycle")
  }
}

///|
fn next_seed(seed : Int) -> Int {
  (seed.to_int64() * 48271L % 2147483647L).to_int()
}

///|
test "1000 seeded DAG schedules are complete bounded and deterministic" {
  let mut seed = 1
  for iteration in 0..<1000 {
    seed = next_seed(seed + iteration + 1)
    let count = 8 + seed % 25
    let jobs = 1 + seed % 8
    let tasks : Array[@scheduler.TaskSpec] = []
    for id in 0..<count {
      let dependencies : Array[Int] = []
      for candidate in 0..<id {
        seed = next_seed(seed)
        if seed % 11 == 0 && dependencies.length() < 4 {
          dependencies.push(candidate)
        }
      }
      tasks.push(@scheduler.TaskSpec::new(id, id, dependencies~))
    }
    let first = @scheduler.build_schedule(tasks, jobs)
    let second = @scheduler.build_schedule(tasks, jobs)
    assert_eq(first, second)
    assert_eq(first.order().length(), count)
    assert_true(first.peak() <= jobs)
    let seen : Set[Int] = Set([])
    for id in first.order() {
      assert_false(seen.contains(id))
      seen.add(id)
    }
    assert_eq(seen.length(), count)
  }
}
