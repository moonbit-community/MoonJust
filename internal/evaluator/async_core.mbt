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
          host_error_detail(error),
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
        host_error_detail(error),
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
    raise effect_failure(
      "call to function `require` failed: could not find executable `" +
      executable +
      "`",
      span,
    )
  } else {
    String(path)
  }
}

///|
async fn[P : @host.HostAsyncProcess] wasm_path_is_executable(
  process : P,
  candidate : @path.PathValue,
  metadata : @host.FileMetadata,
  platform : @host.PlatformInfo,
  pathext : String?,
  context : EvaluationContext,
  span : @source.Span,
) -> Bool raise EvaluationError {
  if platform.operating_system() == Windows {
    return windows_candidate_is_executable(candidate, metadata, pathext)
  }
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
  let path = @host.HostEnv::env_get(host, "PATH") catch {
    error => raise Host(error, span~)
  }
  let platform = @host.HostPlatform::platform_info(host) catch {
    error => raise Host(error, span~)
  }
  let pathext = if platform.operating_system() == Windows {
    @host.HostEnv::env_get(host, "PATHEXT") catch {
      error => raise Host(error, span~)
    }
  } else {
    None
  }
  for
    candidate in which_candidates(
      executable,
      context,
      path.unwrap_or(""),
      platform,
      pathext,
      span,
    ) {
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
      wasm_path_is_executable(
        process, candidate, metadata, platform, pathext, context, span,
      ) {
      return candidate.as_string()
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
  if self.depth > 0 && self.depth % 32 == 0 {
    @async.sleep(0) catch {
      _ =>
        raise Host(InvalidInput("asynchronous evaluation was cancelled"), span~)
    }
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
