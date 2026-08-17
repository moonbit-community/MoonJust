///|
type Value = @value.Value

///|
type EffectHandler = (String, Array[Value], @source.Span) -> Value raise EvaluationError

///|
pub(all) struct EvaluationLimits {
  max_depth : Int
  max_nodes : Int
  max_output_bytes : Int
} derive(Eq, Debug)

///|
pub fn EvaluationLimits::default() -> EvaluationLimits {
  { max_depth: 256, max_nodes: 100_000, max_output_bytes: 64 * 1024 * 1024 }
}

///|
pub fn EvaluationLimits::new(
  max_depth : Int,
  max_nodes : Int,
  max_output_bytes : Int,
) -> EvaluationLimits {
  { max_depth, max_nodes, max_output_bytes }
}

///|
priv struct Evaluator {
  environment : Environment
  limits : EvaluationLimits
  context : EvaluationContext?
  effect_handler : EffectHandler?
  functions : FunctionEnvironment
  mut depth : Int
  mut nodes : Int
}

///|
fn Evaluator::enter(
  self : Evaluator,
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
fn Evaluator::leave(self : Evaluator) -> Unit {
  self.depth -= 1
}

///|
fn Evaluator::check_output(
  self : Evaluator,
  value : Value,
  span : @source.Span,
) -> Value raise EvaluationError {
  if value.to_string().length() > self.limits.max_output_bytes {
    raise OutputLimitExceeded(limit=self.limits.max_output_bytes, span~)
  }
  value
}

///|
fn type_error(
  expected : String,
  value : Value,
  span : @source.Span,
) -> EvaluationError {
  TypeMismatch(expected~, actual=value.kind(), span~)
}

///|
fn apply_value_operator(
  left : Value,
  right : Value,
  separator : String,
  operator : String,
  span : @source.Span,
) -> Value raise EvaluationError {
  let left_display = left.display()
  let right_display = right.display()
  let lhs = left.elements()
  let rhs = right.elements()
  let result : Array[Value] = []
  if lhs.length() == 1 && !rhs.is_empty() {
    for value in rhs {
      result.push(String(lhs[0] + separator + value))
    }
  } else if !lhs.is_empty() && rhs.length() == 1 {
    for value in lhs {
      result.push(String(value + separator + rhs[0]))
    }
  } else if lhs.length() == rhs.length() {
    for index, value in lhs {
      result.push(String(value + separator + rhs[index]))
    }
  } else {
    let message = if lhs.is_empty() || rhs.is_empty() {
      "operator `" + operator + "` cannot be applied to empty lists"
    } else {
      "operator `" +
      operator +
      "` cannot be applied to lists of different lengths: " +
      left_display +
      " " +
      operator +
      " " +
      right_display
    }
    raise Builtin(Failure(message~), span~)
  }
  match result {
    [value] => value
    values => List(values)
  }
}

///|
fn values_equal(left : Value, right : Value) -> Bool {
  left.elements() == right.elements()
}

///|
fn regex_values_match(
  left : Value,
  right : Value,
  span : @source.Span,
) -> Bool raise EvaluationError {
  for value in left.elements() {
    for pattern in right.elements() {
      let matched = @builtin.call("regex_matches", [
        String(value),
        String(pattern),
      ]) catch {
        error => raise Builtin(error, span~)
      }
      if matched.truthy() {
        return true
      }
    }
  }
  false
}

///|
fn builtin_call_failure(
  name : String,
  error : @builtin.BuiltinError,
  span : @source.Span,
) -> Value raise EvaluationError {
  match error {
    Type(actual=List(_) as value, ..) =>
      raise Builtin(
        Failure(
          message="list value " +
            value.display() +
            " passed to `" +
            name +
            "()`\nthe behavior of lists with many built-in functions is undecided\nsee https://github.com/casey/just#lists",
        ),
        span~,
      )
    InvalidPattern(detail~, ..) =>
      raise Builtin(
        Failure(message="call to function `" + name + "` failed: " + detail),
        span~,
      )
    Failure(message~) =>
      raise Builtin(
        Failure(message="call to function `" + name + "` failed: " + message),
        span~,
      )
    _ => raise Builtin(error, span~)
  }
}

///|
fn call_name_span(span : @source.Span, name : String) -> @source.Span {
  @source.Span::new(
    span.source_id(),
    span.start_byte(),
    span.start_byte() + name.length(),
  ) catch {
    _ => span
  }
}

///|
fn evaluate_assert(
  arguments : Array[Value],
  context : EvaluationContext?,
  span : @source.Span,
  condition_text : String,
) -> Value raise EvaluationError {
  if arguments.length() < 1 || arguments.length() > 2 {
    raise Builtin(
      Arity(name="assert", expected="1 or 2", actual=arguments.length()),
      span~,
    )
  }
  let condition = arguments[0]
  if condition.truthy() {
    return match context {
      Some(value) if value.lists() => condition
      _ => String("")
    }
  }
  let message = if arguments.length() == 2 {
    arguments[1].to_string()
  } else {
    "`" + condition_text + "`"
  }
  raise Builtin(Failure(message="assert failed: " + message), span~)
}

///|
fn Evaluator::eval_binary(
  self : Evaluator,
  operator : @syntax.BinaryOperator,
  lhs : @syntax.Expression,
  rhs : @syntax.Expression,
  span : @source.Span,
  operator_span : @source.Span,
) -> Value raise EvaluationError {
  if (operator == Or || operator == And) &&
    self.context.map(fn(value) { !value.lists() }).unwrap_or(false) {
    raise Builtin(
      Failure(message="logical operators require `set lists`"),
      span~,
    )
  }
  if operator == ListConcat &&
    self.context.map(fn(value) { !value.lists() }).unwrap_or(false) {
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
fn Evaluator::eval_defined_function(
  self : Evaluator,
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
  let nested : Evaluator = {
    environment: scope,
    limits: self.limits,
    context: self.context,
    effect_handler: self.effect_handler,
    functions: self.functions,
    depth: self.depth,
    nodes: self.nodes,
  }
  let value = nested.eval(definition.body())
  self.nodes = nested.nodes
  value
}

///|
fn Evaluator::eval_inner(
  self : Evaluator,
  expression : @syntax.Expression,
) -> Value raise EvaluationError {
  let span = expression.span()
  self.enter(span) catch {
    RecursionLimitExceeded(limit~, ..) =>
      match expression {
        Call(name~, ..) if self.functions.get(name) is Some(_) =>
          raise FunctionRecursionLimit(name~, limit~, span~)
        _ => raise RecursionLimitExceeded(limit~, span~)
      }
    error => raise error
  }
  let result : Value = match expression {
    String(literal) => String(literal.cooked())
    Backtick(literal) =>
      match self.effect_handler {
        Some(handler) => handler("backtick", [String(literal.cooked())], span)
        None => raise EffectRequired(effect="process", span~)
      }
    Boolean(value~, ..) => Bool(value)
    Variable(name~, ..) =>
      match self.environment.get(name) {
        Some(value) => value
        None => raise UndefinedVariable(name~, span~)
      }
    Call(name~, arguments~, ..) => {
      let call_span = call_name_span(span, name)
      match self.functions.get(name) {
        Some(definition) =>
          self.eval_defined_function(definition, arguments, call_span)
        None if name == "assert" => {
          let values : Array[Value] = []
          for argument in arguments {
            values.push(self.eval(argument))
          }
          evaluate_assert(
            values,
            self.context,
            call_span,
            arguments.get(0).map(@formatter.expression_text).unwrap_or(""),
          )
        }
        None if @builtin.is_effectful(name) =>
          match self.context {
            None => raise EffectRequired(effect=name, span=call_span)
            Some(context) => {
              let values : Array[Value] = []
              for argument in arguments {
                values.push(self.eval(argument))
              }
              match context_builtin(name, values, context, call_span) {
                Some(value) => value
                None =>
                  match self.effect_handler {
                    Some(handler) => handler(name, values, call_span)
                    None => raise EffectRequired(effect=name, span=call_span)
                  }
              }
            }
          }
        None => {
          let values : Array[Value] = []
          for argument in arguments {
            values.push(self.eval(argument))
          }
          match self.context {
            Some(context) =>
              match context_builtin(name, values, context, call_span) {
                Some(value) => value
                None =>
                  @builtin.call(name, values) catch {
                    error => builtin_call_failure(name, error, call_span)
                  }
              }
            None =>
              @builtin.call(name, values) catch {
                error => builtin_call_failure(name, error, call_span)
              }
          }
        }
      }
    }
    List(elements~, ..) => {
      match self.context {
        Some(context) if !context.lists() =>
          raise Builtin(
            Failure(message="list literals require `set lists`"),
            span=call_name_span(span, "["),
          )
        _ => ()
      }
      let values : Array[Value] = []
      for element in elements {
        values.push(self.eval(element))
      }
      List(values)
    }
    Parenthesized(expression~, ..) => self.eval(expression)
    Unary(operator=Not, operand~, ..) => {
      if self.context.map(fn(value) { !value.lists() }).unwrap_or(false) {
        raise Builtin(
          Failure(message="negation operator requires `set lists`"),
          span~,
        )
      }
      Bool(!self.eval(operand).truthy())
    }
    Binary(operator~, operator_span~, lhs~, rhs~, ..) =>
      self.eval_binary(operator, lhs, rhs, span, operator_span)
    Conditional(condition~, then_branch~, else_branch~, ..) =>
      if self.eval(condition).truthy() {
        self.eval(then_branch)
      } else {
        match else_branch {
          Some(value) => self.eval(value)
          None => List([])
        }
      }
    Format(start~, parts~, ..) => {
      let builder = StringBuilder()
      builder.write_string(start.cooked())
      for part in parts {
        builder.write_string(self.eval(part.expression()).to_string())
        builder.write_string(part.literal().cooked())
      }
      let value = builder.to_string()
      String(
        match start.kind() {
          TripleRaw | TripleCooked => @parser.unindent_string(value)
          _ => value
        },
      )
    }
  }
  self.leave()
  self.check_output(result, span)
}

///|
/// Keep the mutable depth counter balanced even when a nested evaluation
/// raises. This is important when a caller reuses an evaluator after a
/// recoverable diagnostic.
fn Evaluator::eval(
  self : Evaluator,
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
/// Evaluate one expression without host capabilities.
pub fn evaluate(
  expression : @syntax.Expression,
  environment? : Environment = Environment::new(),
  limits? : EvaluationLimits = EvaluationLimits::default(),
  functions? : FunctionEnvironment,
) -> Value raise EvaluationError {
  let functions = functions.unwrap_or(environment.functions())
  let evaluator : Evaluator = {
    environment,
    limits,
    context: None,
    effect_handler: None,
    functions,
    depth: 0,
    nodes: 0,
  }
  evaluator.eval(expression)
}

///|
pub fn evaluate_with_context(
  expression : @syntax.Expression,
  context : EvaluationContext,
  environment? : Environment = Environment::new(),
  limits? : EvaluationLimits = EvaluationLimits::default(),
  functions? : FunctionEnvironment,
) -> Value raise EvaluationError {
  let functions = functions.unwrap_or(environment.functions())
  let evaluator : Evaluator = {
    environment,
    limits,
    context: Some(context),
    effect_handler: None,
    functions,
    depth: 0,
    nodes: 0,
  }
  evaluator.eval(expression)
}

///|
/// Evaluate one expression with process-backed effects. The handler is kept
/// inside the evaluator so nested format/list/binary expressions use identical
/// recursion limits and diagnostics as pure evaluation.
pub fn[
  T : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostProcess + @host.HostPlatform + @host.HostTerminal,
] evaluate_with_effects(
  host : T,
  expression : @syntax.Expression,
  context : EvaluationContext,
  shell : EffectShell,
  quiet? : Bool = false,
  environment? : Environment = Environment::new(),
  limits? : EvaluationLimits = EvaluationLimits::default(),
  functions? : FunctionEnvironment,
) -> Value raise EvaluationError {
  let functions = functions.unwrap_or(environment.functions())
  let handler : EffectHandler = fn(
    name,
    arguments,
    span,
  ) -> Value raise EvaluationError {
    if name == "shell" || name == "backtick" {
      call_shell_effect(
        host,
        arguments,
        context,
        shell,
        span,
        quiet~,
        shell_function=name == "shell",
      )
    } else {
      call_effect_with_context(host, name, arguments, context, span)
    }
  }
  let evaluator : Evaluator = {
    environment,
    limits,
    context: Some(context),
    effect_handler: Some(handler),
    functions,
    depth: 0,
    nodes: 0,
  }
  evaluator.eval(expression)
}

///|
/// Evaluate all assignments, deferring forward references and rejecting cycles.
pub fn evaluate_compilation(
  compilation : @semantic.Compilation,
  environment? : Environment = Environment::new(),
  limits? : EvaluationLimits = EvaluationLimits::default(),
  overrides? : ArrayView[(String, String)] = [],
) -> Environment raise EvaluationError {
  let deferred = LazyEnvironment::new(compilation, environment~, limits~)
  deferred.apply_overrides(overrides)
  deferred.materialize()
}

///|
/// Parse and evaluate one source expression.
pub fn evaluate_source(
  source : @source.Source,
  environment? : Environment = Environment::new(),
  limits? : EvaluationLimits = EvaluationLimits::default(),
) -> Value raise EvaluationError {
  let expression = @parser.parse_expression(source) catch {
    error => raise Parse(error)
  }
  evaluate(expression, environment~, limits~)
}
