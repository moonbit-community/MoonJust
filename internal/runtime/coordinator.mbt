///|
/// A small deterministic coordinator for recipe execution.
///
/// Plans are already topologically ordered by the planner.  That invariant
/// lets the runtime keep dependency state in dense arrays and avoid allocating
/// one async task and one dependency-handle list per recipe.
priv struct ExecutionCoordinator {
  mutex : @async.Mutex
  wake : @async.Semaphore
  remaining : Array[Int]
  blocked : Array[Bool]
  dependents : Array[Array[Int]]
  order : Array[Int]
  output_order : Array[Int]
  ready : Array[Int]
  mut completed : Int
  workers : Int
  total : Int
}

///|
fn ExecutionCoordinator::coordinator_compare(
  self : ExecutionCoordinator,
  left : Int,
  right : Int,
) -> Int {
  let order = self.order[left].compare(self.order[right])
  if order != 0 {
    order
  } else {
    left.compare(right)
  }
}

///|
fn ExecutionCoordinator::coordinator_push_ready(
  self : ExecutionCoordinator,
  id : Int,
) -> Unit {
  self.ready.push(id)
  let mut index = self.ready.length() - 1
  while index > 0 {
    let parent = (index - 1) / 2
    if self.coordinator_compare(self.ready[parent], self.ready[index]) <= 0 {
      break
    }
    let parent_id = self.ready[parent]
    self.ready[parent] = self.ready[index]
    self.ready[index] = parent_id
    index = parent
  }
}

///|
fn ExecutionCoordinator::coordinator_pop_ready(
  self : ExecutionCoordinator,
) -> Int {
  let first = self.ready[0]
  let last = self.ready.pop().unwrap()
  if !self.ready.is_empty() {
    self.ready[0] = last
    let mut index = 0
    while true {
      let left = index * 2 + 1
      if left >= self.ready.length() {
        break
      }
      let right = left + 1
      let child = if right < self.ready.length() &&
        self.coordinator_compare(self.ready[right], self.ready[left]) < 0 {
        right
      } else {
        left
      }
      if self.coordinator_compare(self.ready[index], self.ready[child]) <= 0 {
        break
      }
      let parent_id = self.ready[index]
      self.ready[index] = self.ready[child]
      self.ready[child] = parent_id
      index = child
    }
  }
  first
}

///|
fn execution_coordinator(
  tasks : ArrayView[@planner.ExecutionTask],
  workers : Int,
) -> ExecutionCoordinator? {
  if workers <= 0 || tasks.is_empty() {
    return None
  }
  let total = tasks.length()
  let remaining : Array[Int] = []
  let blocked : Array[Bool] = []
  let dependents : Array[Array[Int]] = []
  let order : Array[Int] = []
  for index, task in tasks {
    if task.id() != index {
      return None
    }
    remaining.push(task.dependencies().length())
    blocked.push(false)
    dependents.push([])
    order.push(task.order())
    for dependency in task.dependencies() {
      // The planner emits dense, topologically ordered IDs.  Rejecting
      // anything else keeps readiness updates bounded and cycle-free.
      if dependency < 0 || dependency >= task.id() {
        return None
      }
      dependents[dependency].push(task.id())
    }
  }
  let output_order : Array[Int] = []
  for id in 0..<total {
    output_order.push(id)
  }
  let coordinator = {
    mutex: Mutex(),
    wake: Semaphore(total + workers + 1, initial_value=0),
    remaining,
    blocked,
    dependents,
    order,
    output_order,
    ready: [],
    completed: 0,
    workers,
    total,
  }
  coordinator.output_order.sort_by(fn(left, right) {
    let compared = coordinator.coordinator_compare(left, right)
    compared
  })
  for id in 0..<total {
    if coordinator.remaining[id] == 0 {
      coordinator.coordinator_push_ready(id)
      coordinator.wake.release()
    }
  }
  Some(coordinator)
}

///|
fn ExecutionCoordinator::output_order(
  self : ExecutionCoordinator,
) -> ArrayView[Int] {
  self.output_order[:]
}

///|
async fn ExecutionCoordinator::next(
  self : ExecutionCoordinator,
) -> (Int, Bool)? {
  while true {
    self.wake.acquire()
    self.mutex.acquire()
    if !self.ready.is_empty() {
      let id = self.coordinator_pop_ready()
      let is_blocked = self.blocked[id]
      self.mutex.release()
      return Some((id, is_blocked))
    }
    let finished = self.completed == self.total
    self.mutex.release()
    if finished {
      return None
    }
  } nobreak {
    None
  }
}

///|
async fn ExecutionCoordinator::finish(
  self : ExecutionCoordinator,
  id : Int,
  failed : Bool,
) -> Unit {
  self.mutex.acquire()
  if failed {
    self.blocked[id] = true
  }
  self.completed += 1
  let mut newly_ready = 0
  for child in self.dependents[id] {
    if failed {
      self.blocked[child] = true
    }
    self.remaining[child] -= 1
    if self.remaining[child] == 0 {
      self.coordinator_push_ready(child)
      newly_ready += 1
    }
  }
  let finished = self.completed == self.total
  self.mutex.release()
  for _ in 0..<newly_ready {
    self.wake.release()
  }
  if finished {
    // Wake every idle worker so the task group can terminate without a
    // per-recipe completion handle.
    for _ in 0..<self.workers {
      self.wake.release()
    }
  }
}
