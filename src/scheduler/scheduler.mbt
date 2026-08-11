///|
/// A deterministic scheduler task. `order` is the stable source-order tie
/// breaker used whenever multiple tasks become runnable together.
pub struct TaskSpec {
  id : Int
  order : Int
  dependencies : Array[Int]
} derive(Eq, Debug)

///|
pub fn TaskSpec::new(
  id : Int,
  order : Int,
  dependencies? : Array[Int] = [],
) -> TaskSpec {
  { id, order, dependencies: dependencies.copy() }
}

///|
pub fn TaskSpec::id(self : TaskSpec) -> Int {
  self.id
}

///|
pub fn TaskSpec::order(self : TaskSpec) -> Int {
  self.order
}

///|
pub fn TaskSpec::dependencies(self : TaskSpec) -> ArrayView[Int] {
  self.dependencies[:]
}

///|
pub(all) suberror SchedulerError {
  InvalidJobs(Int)
  DuplicateTask(Int)
  UnknownDependency(task~ : Int, dependency~ : Int)
  SelfDependency(Int)
  DependencyCycle(Array[Int])
} derive(Eq, Debug)

///|
pub struct Schedule {
  jobs : Int
  waves : Array[Array[Int]]
  order : Array[Int]
} derive(Eq, Debug)

///|
pub fn Schedule::jobs(self : Schedule) -> Int {
  self.jobs
}

///|
pub fn Schedule::waves(self : Schedule) -> ArrayView[Array[Int]] {
  self.waves[:]
}

///|
pub fn Schedule::order(self : Schedule) -> ArrayView[Int] {
  self.order[:]
}

///|
pub fn Schedule::peak(self : Schedule) -> Int {
  let mut result = 0
  for wave in self.waves {
    result = Int::max(result, wave.length())
  }
  result
}

///|
fn compare_task(left : TaskSpec, right : TaskSpec) -> Int {
  let order = left.order().compare(right.order())
  if order != 0 {
    order
  } else {
    left.id().compare(right.id())
  }
}

///|
fn ready(task : TaskSpec, completed : Set[Int]) -> Bool {
  for dependency in task.dependencies() {
    if !completed.contains(dependency) {
      return false
    }
  }
  true
}

///|
/// Build stable execution waves for a bounded scheduler. The model is pure and
/// is used by stress tests as the reference for runtime readiness and fairness.
pub fn build_schedule(
  input : ArrayView[TaskSpec],
  jobs : Int,
) -> Schedule raise SchedulerError {
  if jobs <= 0 {
    raise InvalidJobs(jobs)
  }
  let tasks = input.to_owned()
  tasks.sort_by(compare_task)
  let ids : Set[Int] = Set([])
  for task in tasks {
    if ids.contains(task.id()) {
      raise DuplicateTask(task.id())
    }
    ids.add(task.id())
  }
  for task in tasks {
    for dependency in task.dependencies() {
      if dependency == task.id() {
        raise SelfDependency(task.id())
      }
      if !ids.contains(dependency) {
        raise UnknownDependency(task=task.id(), dependency~)
      }
    }
  }
  let completed : Set[Int] = Set([])
  let waves : Array[Array[Int]] = []
  let order : Array[Int] = []
  while completed.length() < tasks.length() {
    let runnable : Array[Int] = []
    for task in tasks {
      if !completed.contains(task.id()) && ready(task, completed) {
        runnable.push(task.id())
      }
    }
    if runnable.is_empty() {
      let blocked : Array[Int] = []
      for task in tasks {
        if !completed.contains(task.id()) {
          blocked.push(task.id())
        }
      }
      raise DependencyCycle(blocked)
    }
    let count = Int::min(jobs, runnable.length())
    let wave = runnable[:count].to_owned()
    for id in wave {
      completed.add(id)
      order.push(id)
    }
    waves.push(wave)
  }
  { jobs, waves, order }
}

///|
/// Select the first failure in stable schedule order, independent of completion
/// timing. `failures` may arrive in any order from concurrent workers.
pub fn deterministic_failure(
  schedule : Schedule,
  failures : ArrayView[Int],
) -> Int? {
  let failed : Set[Int] = Set(failures)
  for id in schedule.order() {
    if failed.contains(id) {
      return Some(id)
    }
  }
  None
}
