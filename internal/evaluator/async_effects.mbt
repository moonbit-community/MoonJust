///|
pub async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] evaluate_with_async_effects(
  process : P,
  host : H,
  expression : @syntax.Expression,
  context : EvaluationContext,
  shell : EffectShell,
  quiet? : Bool = false,
  dry_run? : Bool = false,
  environment? : Environment = Environment::new(),
  limits? : EvaluationLimits = EvaluationLimits::default(),
  functions? : FunctionEnvironment,
) -> Value raise EvaluationError {
  let functions = functions.unwrap_or(environment.functions())
  let evaluator : AsyncEvaluator[P, H] = {
    process,
    host,
    environment,
    limits,
    context,
    shell,
    functions,
    quiet,
    dry_run,
    depth: 0,
    nodes: 0,
  }
  evaluator.eval(expression)
}

///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] resolve_async_assignment(
  process : P,
  host : H,
  compilation : @semantic.Compilation,
  name : String,
  environment : Environment,
  states : Map[String, LazyState],
  stack : Array[String],
  context : EvaluationContext,
  shell : EffectShell,
  quiet : Bool,
  dry_run : Bool,
  limits : EvaluationLimits,
) -> Value raise EvaluationError {
  match states.get(name) {
    Some(Evaluated(value)) => return value
    Some(Evaluating) => {
      guard compilation.variable(name) is Some(assignment) else {
        raise UndefinedVariable(
          name~,
          span=@source.Span::origin(compilation.source_id()),
        )
      }
      let cycle : Array[String] = []
      let mut inside = false
      for frame in stack {
        if frame == name {
          inside = true
        }
        if inside {
          cycle.push(frame)
        }
      }
      cycle.push(name)
      raise VariableCycle(
        name~,
        stack=cycle,
        span=call_name_span(assignment.span(), name),
      )
    }
    Some(Unevaluated) => ()
    None =>
      match environment.get(name) {
        Some(value) => return value
        None =>
          raise UndefinedVariable(
            name~,
            span=@source.Span::origin(compilation.source_id()),
          )
      }
  }
  guard compilation.variable(name) is Some(assignment) else {
    raise UndefinedVariable(
      name~,
      span=@source.Span::origin(compilation.source_id()),
    )
  }
  if stack.length() >= limits.max_depth {
    raise RecursionLimitExceeded(limit=limits.max_depth, span=assignment.span())
  }
  states[name] = Evaluating
  stack.push(name)
  let value = {
    errdefer {
      ignore(stack.pop())
      states[name] = Unevaluated
    }
    let mut result : Value? = None
    while result is None {
      try
        evaluate_with_async_effects(
          process,
          host,
          assignment.value(),
          context.for_source(assignment.span().source_id()),
          shell,
          quiet~,
          dry_run~,
          environment~,
          limits~,
        )
      catch {
        UndefinedVariable(name=missing, span~) =>
          match compilation.variable(missing) {
            Some(_) =>
              ignore(
                resolve_async_assignment(
                  process, host, compilation, missing, environment, states, stack,
                  context, shell, quiet, dry_run, limits,
                ),
              )
            None => raise UndefinedVariable(name=missing, span~)
          }
        error => raise error
      } noraise {
        evaluated => result = Some(evaluated)
      }
    }
    result.unwrap()
  }
  ignore(stack.pop())
  states[name] = Evaluated(value)
  environment.set(name, value)
  if assignment.exported() || compilation.settings().bool("export") {
    environment.mark_exported(name)
  }
  value
}

///|
/// Materialize assignments lazily while allowing process-backed expressions.
