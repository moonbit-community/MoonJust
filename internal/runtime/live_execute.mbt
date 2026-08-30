///|
pub async fn[
  P : @host.HostAsyncProcess,
  O : @host.HostAsyncOutput,
  S : @host.HostFs + @host.HostAsyncScriptTemp + @host.HostCacheStore,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] execute_plan_live(
  process : P,
  output : O,
  scripts : S,
  effects : H,
  plan : @planner.ExecutionPlan,
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
  // Dry-run planning already materializes every command echo into plan.stderr
  // and deliberately leaves task steps empty. Skip the coordinator and worker
  // pool for this common path while preserving explain preambles.
  if plan.options().dry_run() && plan.steps().is_empty() {
    for task in plan.tasks() {
      ignore(emit_live(output, Stderr, task.preamble(), 0))
    }
    return { commands: 0, }
  }
  let jobs = plan.options().jobs()
  if jobs <= 0 {
    raise live_cache_failure("execution plan jobs must be positive")
  }
  let coordinator = match execution_coordinator(plan.tasks(), jobs) {
    Some(value) => value
    None => raise live_cache_failure("invalid execution task graph")
  }
  let outcomes = try
    @async.with_task_group() <| group => {
      let result : Array[LiveTaskOutcome] = []
      for _ in plan.tasks() {
        result.push(LiveBlocked)
      }
      for _ in 0..<jobs {
        group.spawn(() => {
          while true {
            guard coordinator.next() is Some((id, is_blocked)) else { break }
            let outcome = if is_blocked {
              LiveBlocked
            } else {
              try
                execute_live_task(
                  process,
                  output,
                  scripts,
                  effects,
                  plan.tasks()[id],
                  plan,
                )
              catch {
                error => LiveFailed(error)
              } noraise {
                summary => LiveCompleted(summary)
              }
            }
            result[id] = outcome
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
      result
    }
  catch {
    LiveExecution(..) as failure => raise failure
    _ => raise live_cache_failure("execution task group failed")
  } noraise {
    value => value
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
