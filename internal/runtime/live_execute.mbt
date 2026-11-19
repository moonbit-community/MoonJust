///|
pub async fn[
  P : @host.HostProcess,
  O : @host.HostAsyncOutput,
  S : @host.HostFs + @host.HostScriptTemp + @host.HostCacheStore,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] execute_plan_live(
  process : P,
  output : O,
  scripts : S,
  effects : H,
  plan : @planner.ExecutionPlan,
  confirm : async (String, String) -> Unit raise @planner.ExecutionError,
) -> ExecutionSummary raise LiveRuntimeError {
  ignore(emit_live(output, Stderr, plan.stderr(), 0))
  if plan.tasks().is_empty() {
    return execute_live_steps(
      process,
      output,
      scripts,
      effects,
      plan.steps(),
      plan.options(),
      b""[:],
    )
  }
  let prompt_lock = @async.Mutex()
  async fn run_task(
    task : @planner.ExecutionTask,
  ) -> ExecutionSummary raise LiveRuntimeError {
    if task.confirmation is Some(prompt) {
      prompt_lock.acquire()
      defer prompt_lock.release()
      confirm(task.recipe(), prompt()) catch {
        error => raise live_failure(error, 0)
      }
      return { commands: 0, }
    }
    execute_live_task(process, output, scripts, effects, task, plan)
  }
  let jobs = plan.options().jobs()
  if jobs <= 0 {
    raise live_cache_failure("execution plan jobs must be positive")
  }
  let coordinator = match execution_coordinator(plan.tasks(), jobs) {
    Some(value) => value
    None => raise live_cache_failure("invalid execution task graph")
  }
  let outcomes : Array[LiveTaskOutcome] = []
  try
    @async.with_task_group() <| group => {
      for _ in plan.tasks() {
        outcomes.push(LiveBlocked)
      }
      for _ in 0..<coordinator.workers {
        group.spawn(() => {
          while true {
            guard coordinator.next() is Some((id, is_blocked)) else { break }
            let outcome = if is_blocked {
              LiveBlocked
            } else {
              try run_task(plan.tasks()[id]) catch {
                error => LiveFailed(error)
              } noraise {
                summary => LiveCompleted(summary)
              }
            }
            outcomes[id] = outcome
            coordinator.finish(
              id,
              match outcome {
                LiveFailed(_) | LiveBlocked => true
                LiveCompleted(_) => false
              },
            )
          }
        })
        |> ignore
      }
    }
  catch {
    LiveExecution(..) as failure => raise failure
    _ => raise live_cache_failure("execution task group failed")
  }
  let mut commands = 0
  for id in coordinator.output_order() {
    match outcomes[id] {
      LiveCompleted(summary) => commands += summary.commands()
      LiveFailed(failure) =>
        raise live_failure(
          failure.error(),
          commands + failure.commands(),
          show_message=failure.show_message(),
        )
      LiveBlocked => ()
    }
  }
  { commands, }
}
