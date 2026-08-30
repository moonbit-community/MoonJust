///|
pub async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] evaluate_compilation_with_async_effects(
  process : P,
  host : H,
  compilation : @semantic.Compilation,
  context : EvaluationContext,
  shell : EffectShell,
  environment? : Environment = Environment::new(),
  limits? : EvaluationLimits = EvaluationLimits::default(),
  overrides? : ArrayView[(String, String)] = [],
  quiet? : Bool = false,
  dry_run? : Bool = false,
) -> Environment raise EvaluationError {
  evaluate_compilation_with_async_effects_selected(
    process,
    host,
    compilation,
    context,
    shell,
    compilation.variable_names(),
    environment~,
    limits~,
    overrides~,
    quiet~,
    dry_run~,
  )
}

///|
/// Evaluate an explicit assignment closure with process-backed effects. Any
/// transitive assignment references are resolved on demand and each assignment
/// is evaluated at most once.
pub async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] evaluate_compilation_with_async_effects_selected(
  process : P,
  host : H,
  compilation : @semantic.Compilation,
  context : EvaluationContext,
  shell : EffectShell,
  selected : ArrayView[String],
  environment? : Environment = Environment::new(),
  limits? : EvaluationLimits = EvaluationLimits::default(),
  overrides? : ArrayView[(String, String)] = [],
  quiet? : Bool = false,
  dry_run? : Bool = false,
) -> Environment raise EvaluationError {
  environment.set_functions(FunctionEnvironment::from_compilation(compilation))
  let states : Map[String, LazyState] = Map([])
  for name in compilation.variable_names() {
    environment.remove(name)
    states[name] = Unevaluated
  }
  let unknown : Array[String] = []
  for entry in overrides {
    match compilation.variable(entry.0) {
      Some(assignment) => {
        let value = @value.Value::String(entry.1)
        states[entry.0] = Evaluated(value)
        environment.set(entry.0, value)
        if assignment.exported() || compilation.settings().bool("export") {
          environment.mark_exported(entry.0)
        }
      }
      None if !unknown.contains(entry.0) => unknown.push(entry.0)
      None => ()
    }
  }
  if !unknown.is_empty() {
    unknown.sort()
    let span = @source.Span::origin(compilation.source_id())
    raise UnknownOverrides(names=unknown, span~)
  }
  let stack : Array[String] = []
  for name in selected {
    if compilation.variable(name) is None {
      continue
    }
    ignore(
      resolve_async_assignment(
        process, host, compilation, name, environment, states, stack, context, shell,
        quiet, dry_run, limits,
      ),
    )
  }
  environment
}

///|
pub async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] bind_recipe_parameters_with_async_effects(
  process : P,
  host : H,
  recipe : @syntax.Recipe,
  arguments : Array[@value.Value],
  parent : Environment,
  context : EvaluationContext,
  shell : EffectShell,
  quiet? : Bool = false,
  limits? : EvaluationLimits = EvaluationLimits::default(),
  allow_empty? : Set[String] = Set([]),
) -> Environment raise EvaluationError {
  let parameters = recipe.parameters()
  let mut minimum = 0
  let mut has_variadic = false
  for parameter in parameters {
    if parameter.variadic() {
      has_variadic = true
    }
    if allow_empty.contains(parameter.name()) {
      continue
    } else if parameter.variadic() {
      minimum += parameter.variadic_minimum()
    } else if parameter.default_value() is None {
      minimum += 1
    }
  }
  let maximum = if has_variadic { None } else { Some(parameters.length()) }
  if arguments.length() < minimum ||
    maximum.map(fn(n) { arguments.length() > n }).unwrap_or(false) {
    let expected = match maximum {
      Some(value) if value == minimum => value.to_string()
      Some(value) => minimum.to_string() + " to " + value.to_string()
      None => "at least " + minimum.to_string()
    }
    raise ArgumentCount(
      recipe=recipe.name(),
      expected~,
      actual=arguments.length(),
      span=recipe.span(),
    )
  }
  let scope = Environment::child(parent)
  let mut argument_index = 0
  for parameter in parameters {
    let value : @value.Value = if parameter.variadic() {
      let rest = arguments[argument_index:].to_owned()
      argument_index = arguments.length()
      let value : @value.Value = if rest.is_empty() && !context.lists() {
        String("")
      } else {
        List(rest)
      }
      if parameter.variadic_minimum() > 0 && value.elements().is_empty() {
        raise EmptyParameter(
          recipe=recipe.name(),
          parameter=parameter.name(),
          span=parameter.span(),
        )
      }
      value
    } else if argument_index < arguments.length() {
      let value = arguments[argument_index]
      argument_index += 1
      if value.elements().is_empty() && !allow_empty.contains(parameter.name()) {
        match parameter.default_value() {
          Some(expression) =>
            evaluate_with_async_effects(
              process,
              host,
              expression,
              context,
              shell,
              quiet~,
              environment=scope,
              limits~,
            )
          None =>
            raise EmptyParameter(
              recipe=recipe.name(),
              parameter=parameter.name(),
              span=parameter.span(),
            )
        }
      } else {
        value
      }
    } else {
      match parameter.default_value() {
        Some(expression) =>
          evaluate_with_async_effects(
            process,
            host,
            expression,
            context,
            shell,
            quiet~,
            environment=scope,
            limits~,
          )
        None if allow_empty.contains(parameter.name()) => List([])
        None =>
          raise ArgumentCount(
            recipe=recipe.name(),
            expected="at least " + minimum.to_string(),
            actual=arguments.length(),
            span=parameter.span(),
          )
      }
    }
    scope.set(parameter.name(), value)
    if parameter.exported() {
      scope.mark_exported(parameter.name())
    }
  }
  scope
}
