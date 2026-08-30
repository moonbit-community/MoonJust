///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] AsyncEvaluator::eval_inner(
  self : AsyncEvaluator[P, H],
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
      if self.dry_run {
        String("`" + literal.cooked() + "`")
      } else {
        call_shell_effect_async(
          self.process,
          [String(literal.cooked())],
          self.context,
          self.shell,
          span,
          quiet=self.quiet,
          shell_function=false,
        )
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
        None => {
          let values : Array[Value] = []
          for argument in arguments {
            values.push(self.eval(argument))
          }
          if name == "assert" {
            evaluate_assert(
              values,
              Some(self.context),
              call_span,
              arguments.get(0).map(@formatter.expression_text).unwrap_or(""),
            )
          } else if @builtin.is_effectful(name) {
            match context_builtin(name, values, self.context, call_span) {
              Some(value) => value
              None if @builtin.canonical_name(name) == "shell" =>
                call_shell_effect_async(
                  self.process,
                  values,
                  self.context,
                  self.shell,
                  call_span,
                  quiet=self.quiet,
                )
              None if @builtin.canonical_name(name) == "canonicalize" =>
                canonicalize_effect_async(
                  self.process,
                  self.host,
                  values,
                  self.context,
                  call_span,
                )
              None if @builtin.canonical_name(name) == "which" ||
                @builtin.canonical_name(name) == "require" =>
                which_effect_async(
                  self.process,
                  self.host,
                  @builtin.canonical_name(name),
                  values,
                  self.context,
                  call_span,
                )
              None =>
                call_non_process_effect_with_context(
                  self.host,
                  name,
                  values,
                  self.context,
                  call_span,
                )
            }
          } else {
            match context_builtin(name, values, self.context, call_span) {
              Some(value) => value
              None =>
                @builtin.call(name, values) catch {
                  error => builtin_call_failure(name, error, call_span)
                }
            }
          }
        }
      }
    }
    List(elements~, ..) => {
      if !self.context.lists() {
        raise Builtin(
          Failure(message="list literals require `set lists`"),
          span=call_name_span(span, "["),
        )
      }
      let values : Array[Value] = []
      for element in elements {
        values.push(self.eval(element))
      }
      List(values)
    }
    Parenthesized(expression~, ..) => self.eval(expression)
    Unary(operator=Not, operand~, ..) => {
      if !self.context.lists() {
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
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] AsyncEvaluator::eval(
  self : AsyncEvaluator[P, H],
  expression : @syntax.Expression,
) -> Value raise EvaluationError {
  let before = self.depth
  let result = {
    errdefer (if self.depth > before { self.leave() })
    self.eval_inner(expression)
  }
  result
}

///|
/// Evaluate one expression with asynchronous process effects and synchronous
/// non-process host effects while retaining the regular evaluator limits.
