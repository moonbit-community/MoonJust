///|
type Value = @value.Value

///|
pub(all) struct EvaluationLimits {
  max_depth : Int
  max_nodes : Int
  max_output_bytes : Int
} derive(Eq, Debug)

///|
pub fn EvaluationLimits::default() -> EvaluationLimits {
  { max_depth: 128, max_nodes: 100_000, max_output_bytes: 64 * 1024 * 1024 }
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
fn Evaluator::eval_binary(
  self : Evaluator,
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
fn Evaluator::eval_inner(
  self : Evaluator,
  expression : @syntax.Expression,
) -> Value raise EvaluationError {
  let span = expression.span()
  self.enter(span)
  let result : Value = match expression {
    String(literal) => String(literal.cooked())
    Backtick(_) => raise EffectRequired(effect="process", span~)
    Boolean(value~, ..) => Bool(value)
    Variable(name~, ..) =>
      match self.environment.get(name) {
        Some(value) => value
        None => raise UndefinedVariable(name~, span~)
      }
    Call(name~, arguments~, ..) =>
      if @builtin.is_effectful(name) {
        match self.context {
          None => raise EffectRequired(effect=name, span~)
          Some(context) => {
            let values : Array[Value] = []
            for argument in arguments {
              values.push(self.eval(argument))
            }
            match context_builtin(name, values, context, span) {
              Some(value) => value
              None => raise EffectRequired(effect=name, span~)
            }
          }
        }
      } else {
        let values : Array[Value] = []
        for argument in arguments {
          values.push(self.eval(argument))
        }
        @builtin.call(name, values) catch {
          error => raise Builtin(error, span~)
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
) -> Value raise EvaluationError {
  let evaluator : Evaluator = {
    environment,
    limits,
    context: None,
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
) -> Value raise EvaluationError {
  let evaluator : Evaluator = {
    environment,
    limits,
    context: Some(context),
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
