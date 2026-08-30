///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] async_dependency_arguments(
  process : P,
  host : H,
  dependency : @syntax.Dependency,
  environment : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
) -> Array[@value.Value] raise ExecutionError {
  let result : Array[@value.Value] = []
  let effect_shell = @evaluator.EffectShell::new(
    shell.program(),
    shell.arguments().to_owned(),
  )
  for expression in dependency.arguments() {
    let value = @evaluator.evaluate_with_async_effects(
      process,
      host,
      expression,
      context,
      effect_shell,
      environment~,
    ) catch {
      error => raise Evaluation(error)
    }
    result.push(if context.lists() { value } else { String(value.to_string()) })
  }
  result
}

///|
fn expanded_dependency_argument_sets(
  dependency : @syntax.Dependency,
  values : Array[@value.Value],
) -> Array[Array[@value.Value]] {
  if !dependency.starred() {
    return [values]
  }
  guard dependency.starred_arguments().get(0) is Some(index) else { return [] }
  guard values.get(index) is Some(mapped) else { return [] }
  let elements : Array[@value.Value] = match mapped {
    List(elements) => elements.copy()
    value => value.elements().map(fn(element) { String(element) })
  }
  let result : Array[Array[@value.Value]] = []
  for element in elements {
    let arguments = values.copy()
    arguments[index] = element
    result.push(arguments)
  }
  result
}

///|
fn recipe_has_shebang(recipe : @syntax.Recipe) -> Bool {
  guard recipe.lines().get(0) is Some(line) else { return false }
  guard line.fragments().get(0) is Some(Text(text~, ..)) else { return false }
  text.has_prefix("#!")
}

///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] evaluate_recipe_expression(
  process : P,
  host : H,
  expression : @syntax.Expression,
  environment : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
) -> @value.Value raise ExecutionError {
  @evaluator.evaluate_with_async_effects(
    process,
    host,
    expression,
    context,
    @evaluator.EffectShell::new(shell.program(), shell.arguments().to_owned()),
    environment~,
  ) catch {
    error => raise Evaluation(error)
  }
}

///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] recipe_shell(
  process : P,
  host : H,
  attributes : @semantic.RecipeAttributes?,
  environment : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  fallback : @environment.ShellConfiguration,
) -> @environment.ShellConfiguration raise ExecutionError {
  let value = match attributes {
    Some(value) => value
    None => return fallback
  }
  if value.shell().is_empty() {
    return fallback
  }
  let parts : Array[String] = []
  for expression in value.shell() {
    parts.push(
      evaluate_recipe_expression(
        process, host, expression, environment, context, fallback,
      ).to_string(),
    )
  }
  let program = match parts.get(0) {
    Some(program) if !program.is_empty() => program
    _ => raise Host(InvalidInput("recipe shell must not be empty"))
  }
  @environment.ShellConfiguration::new(program, parts[1:].to_owned()) catch {
    _ => raise Host(InvalidInput("recipe shell is invalid"))
  }
}

///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] recipe_script_interpreter(
  process : P,
  host : H,
  attributes : @semantic.RecipeAttributes?,
  environment : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
  fallback : @environment.ShellConfiguration,
) -> @environment.ShellConfiguration raise ExecutionError {
  guard attributes is Some(value) && !value.script_interpreter().is_empty() else {
    return fallback
  }
  let parts : Array[String] = []
  for expression in value.script_interpreter() {
    parts.push(
      evaluate_recipe_expression(
        process, host, expression, environment, context, shell,
      ).to_string(),
    )
  }
  let program = match parts.get(0) {
    Some(program) if !program.is_empty() => program
    _ => raise Host(InvalidInput("script interpreter must not be empty"))
  }
  @environment.ShellConfiguration::new(program, parts[1:].to_owned()) catch {
    _ => raise Host(InvalidInput("script interpreter is invalid"))
  }
}

///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] recipe_working_directory(
  process : P,
  host : H,
  attributes : @semantic.RecipeAttributes?,
  environment : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
  evaluation_directory : @path.PathValue,
  invocation_directory : @path.PathValue,
  fallback : @path.PathValue,
  recipe : @syntax.Recipe,
) -> @path.PathValue raise ExecutionError {
  let value = match attributes {
    Some(value) => value
    None => return fallback
  }
  let expression = match value.working_directory() {
    Some(expression) => expression
    None if value.no_cd() => return invocation_directory
    None => return fallback
  }
  let evaluated = evaluate_recipe_expression(
    process, host, expression, environment, context, shell,
  )
  if evaluated is List(_) {
    raise InvalidAttributeValue(
      message="list value " +
        evaluated.display() +
        " used as a `[working-directory]` attribute",
      span=recipe_attribute_span(recipe, "working-directory"),
    )
  }
  let text = evaluated.to_string()
  let path = @path.PathValue::new(text, evaluation_directory.flavor()) catch {
    _ => raise Host(InvalidInput("recipe working directory is invalid"))
  }
  evaluation_directory.join(path) catch {
    _ => raise Host(InvalidInput("recipe working directory is invalid"))
  }
}

///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] recipe_process_environment(
  process : P,
  host : H,
  attributes : @semantic.RecipeAttributes?,
  scope : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
  base : ArrayView[(String, String)],
  recipe : @syntax.Recipe,
) -> Array[(String, String)] raise ExecutionError {
  let result = environment_with_exports(base, scope)
  guard attributes is Some(value) else { return result }
  for entry in value.env() {
    let evaluated_key = evaluate_recipe_expression(
      process,
      host,
      entry.0,
      scope,
      context,
      shell,
    )
    if evaluated_key is List(_) {
      raise InvalidAttributeValue(
        message="list value " +
          evaluated_key.display() +
          " used as `env` attribute name",
        span=recipe_attribute_span(recipe, "env"),
      )
    }
    let key = evaluated_key.to_string()
    let evaluated = evaluate_recipe_expression(
      process,
      host,
      entry.1,
      scope,
      context,
      shell,
    )
    let mut replaced = false
    for index, existing in result {
      if existing.0 == key {
        if evaluated.elements().is_empty() {
          ignore(result.remove(index))
        } else {
          result[index] = (key, evaluated.to_string())
        }
        replaced = true
        break
      }
    }
    if !replaced && !evaluated.elements().is_empty() {
      result.push((key, evaluated.to_string()))
    }
  }
  result
}

///|
/// Recognize the common static fan-out shape without entering an evaluator.
/// Aliases, mapped arguments, attributes, parameters, recipe lines, and
/// subsequent dependencies all opt out.
