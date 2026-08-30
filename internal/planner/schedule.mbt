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
  { id, order, dependencies: dependencies.copy(), }
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
fn ready_heap_push(heap : Array[TaskSpec], task : TaskSpec) -> Unit {
  heap.push(task)
  let mut index = heap.length() - 1
  while index > 0 {
    let parent = (index - 1) / 2
    if compare_task(heap[parent], heap[index]) <= 0 {
      break
    }
    let parent_task = heap[parent]
    heap[parent] = heap[index]
    heap[index] = parent_task
    index = parent
  }
}

///|
fn ready_heap_pop(heap : Array[TaskSpec]) -> TaskSpec {
  let first = heap[0]
  let last = heap.pop().unwrap()
  if !heap.is_empty() {
    heap[0] = last
    let mut index = 0
    while true {
      let left = index * 2 + 1
      if left >= heap.length() {
        break
      }
      let right = left + 1
      let child = if right < heap.length() &&
        compare_task(heap[right], heap[left]) < 0 {
        right
      } else {
        left
      }
      if compare_task(heap[index], heap[child]) <= 0 {
        break
      }
      let parent_task = heap[index]
      heap[index] = heap[child]
      heap[child] = parent_task
      index = child
    }
  }
  first
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
  let tasks_by_id : Map[Int, TaskSpec] = Map([])
  let remaining : Map[Int, Int] = Map([])
  let dependents : Map[Int, Array[Int]] = Map([])
  let ready : Array[TaskSpec] = []
  for task in tasks {
    tasks_by_id[task.id()] = task
    remaining[task.id()] = task.dependencies().length()
    if task.dependencies().is_empty() {
      ready_heap_push(ready, task)
    }
    for dependency in task.dependencies() {
      match dependents.get(dependency) {
        Some(children) => children.push(task.id())
        None => dependents[dependency] = [task.id()]
      }
    }
  }
  let completed : Set[Int] = Set([])
  let waves : Array[Array[Int]] = []
  let order : Array[Int] = []
  while completed.length() < tasks.length() {
    if ready.is_empty() {
      let blocked : Array[Int] = []
      for task in tasks {
        if !completed.contains(task.id()) {
          blocked.push(task.id())
        }
      }
      raise DependencyCycle(blocked)
    }
    let count = Int::min(jobs, ready.length())
    let wave_tasks : Array[TaskSpec] = []
    for _ in 0..<count {
      wave_tasks.push(ready_heap_pop(ready))
    }
    let wave : Array[Int] = []
    for task in wave_tasks {
      let id = task.id()
      wave.push(id)
      completed.add(id)
      order.push(id)
      match dependents.get(id) {
        Some(children) =>
          for child in children {
            let child_remaining = remaining.get(child).unwrap() - 1
            remaining[child] = child_remaining
            if child_remaining == 0 {
              ready_heap_push(ready, tasks_by_id.get(child).unwrap())
            }
          }
        None => ()
      }
    }
    waves.push(wave)
  }
  { jobs, waves, order, }
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
