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
  mut depth : Int
  mut nodes : Int
}

///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] canonicalize_effect_async(
  process : P,
  host : H,
  arguments : Array[Value],
  context : EvaluationContext,
  span : @source.Span,
) -> Value raise EvaluationError {
  let platform = @host.HostPlatform::platform_info(host) catch {
    error => raise Host(error, span~)
  }
  if !platform.portable_runtime() {
    return call_non_process_effect_with_context(
      host, "canonicalize", arguments, context, span,
    )
  }
  let name = validate_effect_arity("canonicalize", arguments, span)
  let raw = expect_string(name, arguments, 0, span)
  let path = resolve_context_path(context, raw, span)
  ignore(
    @host.HostFs::metadata(host, path) catch {
      error =>
        raise effect_failure(
          "call to function `canonicalize` failed: I/O error canonicalizing `" +
          raw +
          "`: " +
          Repr(error).to_string(),
          span,
        )
    },
  )
  let spec = @host.CommandSpec::new("/usr/bin/env", [
    "realpath",
    path.as_string(),
  ]) catch {
    error => raise Host(error, span~)
  }
  spec.set_cwd(require_context_path("cwd", context.cwd, span))
  configure_effect_environment(spec, context, span)
  spec.set_stdout(Capture)
  spec.set_stderr(Discard)
  let output = @host.HostAsyncProcess::run_process_async(process, spec) catch {
    error =>
      raise effect_failure(
        "call to function `canonicalize` failed: I/O error canonicalizing `" +
        raw +
        "`: " +
        Repr(error).to_string(),
        span,
      )
  }
  match output.termination() {
    Exited(0) => ()
    _ =>
      raise effect_failure(
        "call to function `canonicalize` failed: I/O error canonicalizing `" +
        raw +
        "`: realpath failed",
        span,
      )
  }
  String(strip_one_line_ending(bytes_text(output.stdout().to_owned(), span)))
}

///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] which_effect_async(
  process : P,
  host : H,
  requested : String,
  arguments : Array[Value],
  context : EvaluationContext,
  span : @source.Span,
) -> Value raise EvaluationError {
  let platform = @host.HostPlatform::platform_info(host) catch {
    error => raise Host(error, span~)
  }
  if !platform.portable_runtime() {
    return call_non_process_effect_with_context(
      host, requested, arguments, context, span,
    )
  }
  let name = validate_effect_arity(requested, arguments, span)
  if name == "which" && !context.lists() {
    raise effect_failure("the `which()` function requires `set lists`", span)
  }
  let executable = expect_string(name, arguments, 0, span)
  let path = which_value_async(process, host, executable, context, span)
  if name == "which" {
    if path == "" {
      List([])
    } else {
      List([String(path)])
    }
  } else if path == "" {
    raise effect_failure("could not find executable `" + executable + "`", span)
  } else {
    String(path)
  }
}

///|
async fn[P : @host.HostAsyncProcess] wasm_path_is_executable(
  process : P,
  candidate : @path.PathValue,
  context : EvaluationContext,
  span : @source.Span,
) -> Bool raise EvaluationError {
  let spec = @host.CommandSpec::new("/bin/test", ["-x", candidate.as_string()]) catch {
    error => raise Host(error, span~)
  }
  spec.set_cwd(require_context_path("cwd", context.cwd, span))
  configure_effect_environment(spec, context, span)
  spec.set_stdout(Discard)
  spec.set_stderr(Discard)
  let result = @host.HostAsyncProcess::run_process_async(process, spec) catch {
    error => raise Host(error, span~)
  }
  result.termination() == Exited(0)
}

///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostPlatform,
] which_value_async(
  process : P,
  host : H,
  executable : String,
  context : EvaluationContext,
  span : @source.Span,
) -> String raise EvaluationError {
  if executable == "" {
    return ""
  }
  let cwd = require_context_path("cwd", context.cwd, span)
  if executable.contains("/") || executable.contains("\\") {
    let candidate = resolve_context_path(context, executable, span)
    let exists = @host.HostFs::file_exists(host, candidate) catch {
      error => raise Host(error, span~)
    }
    if !exists {
      return ""
    }
    let metadata = try @host.HostFs::metadata(host, candidate) catch {
      NotFound(_) => return ""
      error => raise Host(error, span~)
    } noraise {
      value => value
    }
    return if metadata.is_file() &&
      wasm_path_is_executable(process, candidate, context, span) {
      candidate.as_string()
    } else {
      ""
    }
  }
  let path = @host.HostEnv::env_get(host, "PATH") catch {
    error => raise Host(error, span~)
  }
  let platform = @host.HostPlatform::platform_info(host) catch {
    error => raise Host(error, span~)
  }
  let separator = if platform.operating_system() == Windows { ";" } else { ":" }
  let extensions = if platform.operating_system() == Windows {
    ["", ".exe", ".cmd", ".bat", ".com"]
  } else {
    [""]
  }
  for directory in path.unwrap_or("").split(separator) {
    let base = if directory.length() == 0 {
      cwd
    } else {
      @path.PathValue::new(directory.to_owned(), cwd.flavor()) catch {
        _ => continue
      }
    }
    for extension in extensions {
      let child = @path.PathValue::new(executable + extension, cwd.flavor()) catch {
        _ => continue
      }
      let candidate = base.join(child) catch { _ => continue }
      let exists = @host.HostFs::file_exists(host, candidate) catch {
        error => raise Host(error, span~)
      }
      if !exists {
        continue
      }
      let metadata = try @host.HostFs::metadata(host, candidate) catch {
        NotFound(_) => continue
        error => raise Host(error, span~)
      } noraise {
        value => value
      }
      if metadata.is_file() &&
        wasm_path_is_executable(process, candidate, context, span) {
        return candidate.as_string()
      }
    }
  }
  ""
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
    RegexMatch => Bool(regex_values_match(left, right, span))
    RegexNotMatch => Bool(!regex_values_match(left, right, span))
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
    Concat => apply_value_operator(left, right, "", span)
    Join => apply_value_operator(left, right, "/", span)
    Or | And => Bool(false)
  }
}

///|
async fn[
  P : @host.HostAsyncProcess,
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
    Call(name~, arguments~, ..) =>
      match self.functions.get(name) {
        Some(definition) =>
          self.eval_defined_function(definition, arguments, span)
        None => {
          let values : Array[Value] = []
          for argument in arguments {
            values.push(self.eval(argument))
          }
          if name == "assert" {
            evaluate_assert(values, Some(self.context), span)
          } else if @builtin.is_effectful(name) {
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
              None if @builtin.canonical_name(name) == "canonicalize" =>
                canonicalize_effect_async(
                  self.process,
                  self.host,
                  values,
                  self.context,
                  span,
                )
              None if @builtin.canonical_name(name) == "which" ||
                @builtin.canonical_name(name) == "require" =>
                which_effect_async(
                  self.process,
                  self.host,
                  @builtin.canonical_name(name),
                  values,
                  self.context,
                  span,
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
            match context_builtin(name, values, self.context, span) {
              Some(value) => value
              None =>
                @builtin.call(name, values) catch {
                  error => builtin_call_failure(name, error, span)
                }
            }
          }
        }
      }
    List(elements~, ..) => {
      if !self.context.lists() {
        raise Builtin(
          Failure(message="list literals require `set lists`"),
          span~,
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
    Binary(operator~, lhs~, rhs~, ..) =>
      self.eval_binary(operator, lhs, rhs, span)
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
    let span = @source.Span::new(compilation.source_id(), 0, 0) catch {
      _ => abort("valid compilation source origin")
    }
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
