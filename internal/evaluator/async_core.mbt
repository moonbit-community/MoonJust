///|
priv struct AsyncEvaluator[P, H] {
  process : P
  host : H
  environment : Environment
  limits : EvaluationLimits
  context : EvaluationContext
  shell : EffectShell
  functions : FunctionEnvironment
  quiet : Bool
  dry_run : Bool
  mut depth : Int32
  mut nodes : Int32
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
  P : @host.HostProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] AsyncEvaluator::eval_binary(
  self : AsyncEvaluator[P, H],
  operator : @syntax.BinaryOperator,
  lhs : @syntax.Expression,
  rhs : @syntax.Expression,
  span : @source.Span,
  operator_span : @source.Span,
) -> Value raise EvaluationError {
  if (operator == Or || operator == And) && !self.context.lists() {
    raise Builtin(
      Failure(message="logical operators require `set lists`"),
      span~,
    )
  }
  if operator == ListConcat && !self.context.lists() {
    raise Builtin(
      Failure(message="list concatenation operator `++` requires `set lists`"),
      span~,
    )
  }
  if operator == Or {
    let left = self.eval(lhs)
    return if left.truthy() { left } else { self.eval(rhs) }
  }
  if operator == And {
    let left = self.eval(lhs)
    return if left.truthy() { self.eval(rhs) } else { List([]) }
  }
  let left = self.eval(lhs)
  let right = self.eval(rhs)
  match operator {
    Equal => Bool(values_equal(left, right))
    NotEqual => Bool(!values_equal(left, right))
    RegexMatch => Bool(regex_values_match(left, right, operator_span))
    RegexNotMatch => Bool(!regex_values_match(left, right, operator_span))
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
    Concat => apply_value_operator(left, right, "", "+", operator_span)
    Join => apply_value_operator(left, right, "/", "/", operator_span)
    Or | And => Bool(false)
  }
}

///|
async fn[
  P : @host.HostProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] AsyncEvaluator::eval_defined_function(
  self : AsyncEvaluator[P, H],
  definition : @syntax.FunctionDefinition,
  arguments : ArrayView[@syntax.Expression],
  span : @source.Span,
) -> Value raise EvaluationError {
  let expected = definition.parameters().length()
  if arguments.length() != expected {
    raise FunctionArgumentCount(
      name=definition.name(),
      expected~,
      actual=arguments.length(),
      span~,
    )
  }
  let values : Array[Value] = []
  for argument in arguments {
    values.push(self.eval(argument))
  }
  let scope = Environment::child(self.environment)
  for index, parameter in definition.parameters() {
    scope.set(parameter.name(), values[index])
  }
  if self.depth > 0 && self.depth % 32 == 0 {
    @async.sleep(0)
  }
  let nested : AsyncEvaluator[P, H] = {
    process: self.process,
    host: self.host,
    environment: scope,
    limits: self.limits,
    context: self.context.for_source(definition.span().source_id()),
    shell: self.shell,
    functions: self.functions,
    quiet: self.quiet,
    dry_run: self.dry_run,
    depth: self.depth,
    nodes: self.nodes,
  }
  let value = nested.eval(definition.body())
  self.nodes = nested.nodes
  value
}
