///|
pub async fn[
  P : @host.HostAsyncProcess,
  S : @host.HostFs + @host.HostAsyncScriptTemp + @host.HostCacheStore,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] execute_plan(
  process : P,
  scripts : S,
  effects : H,
  plan : @planner.ExecutionPlan,
) -> @planner.ExecutionReport raise RuntimeError {
  if plan.tasks().is_empty() {
    return execute_steps(
      process,
      scripts,
      effects,
      plan.steps(),
      plan.options(),
      plan.stderr(),
    )
  }
  let jobs = plan.options().jobs()
  if jobs <= 0 {
    raise invalid_plan("execution plan jobs must be positive")
  }
  let coordinator = match execution_coordinator(plan.tasks(), jobs) {
    Some(value) => value
    None => raise invalid_plan("invalid execution task graph")
  }
  let outcomes = try
    @async.with_task_group() <| group => {
      let result : Array[TaskOutcome] = []
      for _ in plan.tasks() {
        result.push(Blocked)
      }
      for _ in 0..<jobs {
        group.spawn(() => {
          while true {
            guard coordinator.next() is Some((id, is_blocked)) else { break }
            let outcome = if is_blocked {
              Blocked
            } else {
              try
                execute_task(process, scripts, effects, plan.tasks()[id], plan)
              catch {
                error => Failed(error)
              } noraise {
                report => Completed(report)
              }
            }
            result[id] = outcome
            coordinator.finish(
              id,
              match outcome {
                Failed(_) | Blocked => true
                Completed(_) => false
              },
            )
          }
        })
        |> ignore
      }
      result
    }
  catch {
    Execution(..) as failure => raise failure
    _ => raise invalid_plan("execution task group failed")
  } noraise {
    value => value
  }
  let stdout : Array[Byte] = []
  let stderr : Array[Byte] = []
  for byte in plan.stderr() {
    stderr.push(byte)
  }
  let mut commands = 0
  for id in coordinator.output_order() {
    match outcomes[id] {
      Completed(report) => commands += append_report(stdout, stderr, report)
      Failed(failure) => {
        for byte in failure.stdout() {
          stdout.push(byte)
        }
        for byte in failure.stderr() {
          stderr.push(byte)
        }
        commands += failure.commands()
        raise runtime_failure(failure.error(), stdout, stderr, commands)
      }
      Blocked => ()
    }
  }
  @planner.ExecutionReport::new(
    Bytes::from_array(stdout),
    Bytes::from_array(stderr),
    commands,
  )
}

///|
