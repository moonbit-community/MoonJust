///|
pub(all) enum LazyState {
  Unevaluated
  Evaluating
  Evaluated(@value.Value)
} derive(Eq, Debug)

///|
/// Assignment evaluator with explicit lazy states and a redacted name-only
/// recursion stack.
pub struct LazyEnvironment {
  compilation : @semantic.Compilation
  environment : Environment
  states : Map[String, LazyState]
  stack : Array[String]
  limits : EvaluationLimits
}

///|
pub fn LazyEnvironment::new(
  compilation : @semantic.Compilation,
  environment? : Environment = Environment::new(),
  limits? : EvaluationLimits = EvaluationLimits::default(),
) -> LazyEnvironment {
  environment.set_functions(FunctionEnvironment::from_compilation(compilation))
  let states : Map[String, LazyState] = Map([])
  for name in compilation.variable_names() {
    environment.remove(name)
    states[name] = Unevaluated
  }
  { compilation, environment, states, stack: [], limits }
}

///|
pub fn LazyEnvironment::state(
  self : LazyEnvironment,
  name : String,
) -> LazyState? {
  self.states.get(name)
}

///|
pub fn LazyEnvironment::environment(self : LazyEnvironment) -> Environment {
  self.environment
}

///|
/// Apply command-line variable overrides before any assignment is evaluated.
/// Repeated names are last-wins, and unknown names are reported together
/// without retaining their values.
pub fn LazyEnvironment::apply_overrides(
  self : LazyEnvironment,
  overrides : ArrayView[(String, String)],
) -> Unit raise EvaluationError {
  let unknown : Array[String] = []
  for entry in overrides {
    let name = entry.0
    match self.compilation.variable(name) {
      Some(assignment) => {
        let value = @value.Value::String(entry.1)
        self.states[name] = Evaluated(value)
        self.environment.set(name, value)
        if assignment.exported() || self.compilation.settings().bool("export") {
          self.environment.mark_exported(name)
        }
      }
      None if !unknown.contains(name) => unknown.push(name)
      None => ()
    }
  }
  if !unknown.is_empty() {
    unknown.sort()
    let span = @source.Span::origin(self.compilation.source_id())
    raise UnknownOverrides(names=unknown, span~)
  }
}

///|
fn LazyEnvironment::cycle(
  self : LazyEnvironment,
  name : String,
  span : @source.Span,
) -> EvaluationError {
  let cycle : Array[String] = []
  let mut inside = false
  for frame in self.stack {
    if frame == name {
      inside = true
    }
    if inside {
      cycle.push(frame)
    }
  }
  cycle.push(name)
  let name_span = @source.Span::new(
    span.source_id(),
    span.start_byte(),
    span.start_byte() + name.length(),
  ) catch {
    _ => span
  }
  VariableCycle(name~, stack=cycle, span=name_span)
}

///|
fn LazyEnvironment::resolve_body(
  self : LazyEnvironment,
  assignment : @syntax.Assignment,
) -> @value.Value raise EvaluationError {
  self.evaluate_expression(assignment.value())
}

///|
/// Evaluate one expression while resolving only the assignments it actually
/// references. This is used by const-like settings that must be known before
/// effectful global assignments are evaluated.
pub fn LazyEnvironment::evaluate_expression(
  self : LazyEnvironment,
  expression : @syntax.Expression,
) -> @value.Value raise EvaluationError {
  for ;; {
    try
      evaluate(expression, environment=self.environment, limits=self.limits)
    catch {
      UndefinedVariable(name~, span~) =>
        match self.compilation.variable(name) {
          Some(_) => ignore(self.resolve(name))
          None => raise UndefinedVariable(name~, span~)
        }
      error => raise error
    } noraise {
      value => return value
    }
  }
}

///|
pub fn LazyEnvironment::resolve(
  self : LazyEnvironment,
  name : String,
) -> @value.Value raise EvaluationError {
  match self.states.get(name) {
    Some(Evaluated(value)) => return value
    Some(Evaluating) => {
      guard self.compilation.variable(name) is Some(assignment) else {
        raise UndefinedVariable(
          name~,
          span=@source.Span::origin(self.compilation.source_id()),
        )
      }
      raise self.cycle(name, assignment.span())
    }
    Some(Unevaluated) => ()
    None =>
      match self.environment.get(name) {
        Some(value) => return value
        None =>
          raise UndefinedVariable(
            name~,
            span=@source.Span::origin(self.compilation.source_id()),
          )
      }
  }
  guard self.compilation.variable(name) is Some(assignment) else {
    raise UndefinedVariable(
      name~,
      span=@source.Span::origin(self.compilation.source_id()),
    )
  }
  if self.stack.length() >= self.limits.max_depth {
    raise RecursionLimitExceeded(
      limit=self.limits.max_depth,
      span=assignment.span(),
    )
  }
  self.states[name] = Evaluating
  self.stack.push(name)
  errdefer {
    ignore(self.stack.pop())
    self.states[name] = Unevaluated
  }
  let value = self.resolve_body(assignment)
  ignore(self.stack.pop())
  self.states[name] = Evaluated(value)
  self.environment.set(name, value)
  if assignment.exported() || self.compilation.settings().bool("export") {
    self.environment.mark_exported(name)
  }
  value
}

///|
pub fn LazyEnvironment::materialize(
  self : LazyEnvironment,
) -> Environment raise EvaluationError {
  for name in self.compilation.variable_names() {
    ignore(self.resolve(name))
  }
  self.environment
}
