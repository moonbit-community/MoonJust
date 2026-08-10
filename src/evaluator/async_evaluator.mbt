///|
priv struct AsyncEvaluator[P, H] {
  process : P
  host : H
  environment : Environment
  limits : EvaluationLimits
  context : EvaluationContext
  shell : EffectShell
  quiet : Bool
  mut depth : Int
  mut nodes : Int
}

///|
fn[P, H] AsyncEvaluator::enter(
  self : AsyncEvaluator[P, H],
  span : @source.Span,
) -> Unit raise EvaluationError {
  if self.depth >= self.limits.max_depth {
    raise RecursionLimitExceeded(limit=self.limits.max_depth, span~)
  }
  if self.nodes >= self.limits.max_nodes {
    raise NodeLimitExceeded(limit=self.limits.max_nodes, span~)
  }
  self.depth += 1
  self.nodes += 1
}

///|
fn[P, H] AsyncEvaluator::leave(self : AsyncEvaluator[P, H]) -> Unit {
  self.depth -= 1
}

///|
fn[P, H] AsyncEvaluator::check_output(
  self : AsyncEvaluator[P, H],
  value : Value,
  span : @source.Span,
) -> Value raise EvaluationError {
  if value.to_string().length() > self.limits.max_output_bytes {
    raise OutputLimitExceeded(limit=self.limits.max_output_bytes, span~)
  }
  value
}

///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] AsyncEvaluator::eval_binary(
  self : AsyncEvaluator[P, H],
  operator : @syntax.BinaryOperator,
  lhs : @syntax.Expression,
  rhs : @syntax.Expression,
  span : @source.Span,
) -> Value raise EvaluationError {
  if operator == Or {
    let left = self.eval(lhs)
    return Bool(left.truthy() || self.eval(rhs).truthy())
  }
  if operator == And {
    let left = self.eval(lhs)
    return Bool(left.truthy() && self.eval(rhs).truthy())
  }
  let left = self.eval(lhs)
  let right = self.eval(rhs)
  match operator {
    Equal => Bool(left == right)
    NotEqual => Bool(left != right)
    RegexMatch | RegexNotMatch => {
      let matched = @builtin.call("regex_matches", [left, right]) catch {
        error => raise Builtin(error, span~)
      }
      if operator == RegexNotMatch {
        Bool(!matched.truthy())
      } else {
        matched
      }
    }
    ListConcat =>
      match (left, right) {
        (List(first), List(second)) => {
          let result = first.copy()
          for value in second {
            result.push(value)
          }
          List(result)
        }
        _ => raise type_error("two lists", left, span)
      }
    Concat => String(left.to_string() + right.to_string())
    Join =>
      @builtin.call("path_join", [
        String(left.to_string()),
        String(right.to_string()),
      ]) catch {
        error => raise Builtin(error, span~)
      }
    Or | And => Bool(false)
  }
}

///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] AsyncEvaluator::eval_inner(
  self : AsyncEvaluator[P, H],
  expression : @syntax.Expression,
) -> Value raise EvaluationError {
  let span = expression.span()
  self.enter(span)
  let result : Value = match expression {
    String(literal) => String(literal.cooked())
    Backtick(literal) =>
      call_shell_effect_async(
        self.process,
        [String(literal.cooked())],
        self.context,
        self.shell,
        span,
        quiet=self.quiet,
      )
    Boolean(value~, ..) => Bool(value)
    Variable(name~, ..) =>
      match self.environment.get(name) {
        Some(value) => value
        None => raise UndefinedVariable(name~, span~)
      }
    Call(name~, arguments~, ..) => {
      let values : Array[Value] = []
      for argument in arguments {
        values.push(self.eval(argument))
      }
      if @builtin.is_effectful(name) {
        match context_builtin(name, values, self.context, span) {
          Some(value) => value
          None if @builtin.canonical_name(name) == "shell" =>
            call_shell_effect_async(
              self.process,
              values,
              self.context,
              self.shell,
              span,
              quiet=self.quiet,
            )
          None =>
            call_non_process_effect_with_context(
              self.host,
              name,
              values,
              self.context,
              span,
            )
        }
      } else {
        @builtin.call(name, values) catch {
          error => raise Builtin(error, span~)
        }
      }
    }
    List(elements~, ..) => {
      let values : Array[Value] = []
      for element in elements {
        values.push(self.eval(element))
      }
      List(values)
    }
    Unary(operator=Not, operand~, ..) => Bool(!self.eval(operand).truthy())
    Binary(operator~, lhs~, rhs~, ..) =>
      self.eval_binary(operator, lhs, rhs, span)
    Conditional(condition~, then_branch~, else_branch~, ..) =>
      if self.eval(condition).truthy() {
        self.eval(then_branch)
      } else {
        match else_branch {
          Some(value) => self.eval(value)
          None => String("")
        }
      }
    Format(start~, parts~, ..) => {
      let builder = StringBuilder()
      builder.write_string(start.cooked())
      for part in parts {
        builder.write_string(self.eval(part.expression()).to_string())
        builder.write_string(part.literal().cooked())
      }
      String(builder.to_string())
    }
  }
  self.leave()
  self.check_output(result, span)
}

///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] AsyncEvaluator::eval(
  self : AsyncEvaluator[P, H],
  expression : @syntax.Expression,
) -> Value raise EvaluationError {
  let before = self.depth
  try self.eval_inner(expression) catch {
    error => {
      if self.depth > before {
        self.leave()
      }
      raise error
    }
  } noraise {
    value => value
  }
}

///|
/// Evaluate one expression with asynchronous process effects and synchronous
/// non-process host effects while retaining the regular evaluator limits.
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
  environment? : Environment = Environment::new(),
  limits? : EvaluationLimits = EvaluationLimits::default(),
) -> Value raise EvaluationError {
  let evaluator : AsyncEvaluator[P, H] = {
    process,
    host,
    environment,
    limits,
    context,
    shell,
    quiet,
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
  limits : EvaluationLimits,
) -> Value raise EvaluationError {
  match states.get(name) {
    Some(Evaluated(value)) => return value
    Some(Evaluating) => {
      let assignment = compilation.variable(name).unwrap()
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
      raise VariableCycle(name~, stack=cycle, span=assignment.span())
    }
    Some(Unevaluated) => ()
    None =>
      match environment.get(name) {
        Some(value) => return value
        None => {
          let span = @source.Span::new(compilation.source_id(), 0, 0) catch {
            _ => abort("valid compilation source origin")
          }
          raise UndefinedVariable(name~, span~)
        }
      }
  }
  let assignment = compilation.variable(name).unwrap()
  if stack.length() >= limits.max_depth {
    raise RecursionLimitExceeded(limit=limits.max_depth, span=assignment.span())
  }
  states[name] = Evaluating
  stack.push(name)
  let value = try {
    let mut result : Value? = None
    while result is None {
      try
        evaluate_with_async_effects(
          process,
          host,
          assignment.value(),
          context,
          shell,
          quiet~,
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
                  context, shell, quiet, limits,
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
  } catch {
    error => {
      ignore(stack.pop())
      states[name] = Unevaluated
      raise error
    }
  } noraise {
    evaluated => evaluated
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
) -> Environment raise EvaluationError {
  let states : Map[String, LazyState] = Map([])
  for name in compilation.variable_names() {
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
    let span = @source.Span::new(compilation.source_id(), 0, 0) catch {
      _ => abort("valid compilation source origin")
    }
    raise UnknownOverrides(names=unknown, span~)
  }
  let stack : Array[String] = []
  for name in compilation.variable_names() {
    ignore(
      resolve_async_assignment(
        process, host, compilation, name, environment, states, stack, context, shell,
        quiet, limits,
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
) -> Environment raise EvaluationError {
  let parameters = recipe.parameters()
  let mut minimum = 0
  let mut has_variadic = false
  for parameter in parameters {
    if parameter.variadic() {
      minimum += parameter.variadic_minimum()
      has_variadic = true
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
      List(rest)
    } else if argument_index < arguments.length() {
      let value = arguments[argument_index]
      argument_index += 1
      value
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
        None => abort("argument bounds validated above")
      }
    }
    scope.set(parameter.name(), value)
    if parameter.exported() {
      scope.mark_exported(parameter.name())
    }
  }
  scope
}
