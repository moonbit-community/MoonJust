///|
fn plan_recipe_lines(
  recipe : @syntax.Recipe,
  environment : @evaluator.Environment,
  shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  process_environment : ArrayView[(String, String)],
  options : ExecutionOptions,
  commands : Array[PlannedCommand],
  stderr : Array[Byte],
) -> Unit raise ExecutionError {
  for index, source_line in recipe.lines() {
    let line = evaluate_line(source_line, environment)
    if options.dry_run() ||
      options.verbose() ||
      options.timestamp() is Some(_) ||
      (!options.quiet() && !recipe.quiet() && !line.quiet) {
      append_bytes(
        stderr,
        render_command_echo(
          line.command,
          timestamp=options.timestamp(),
          color=options.command_color(),
        )[:],
      )
    }
    if !options.dry_run() && !line.command.is_empty() {
      commands.push(
        PlannedCommand::new(
          command_spec(
            shell,
            line.command,
            cwd,
            process_environment,
            options.quiet(),
          ),
          recipe.name(),
          index + 1,
          line.ignore_error,
        ),
      )
    }
  }
}

///|
fn environment_with_exports(
  base : ArrayView[(String, String)],
  scope : @evaluator.Environment,
) -> Array[(String, String)] {
  let result = base.to_owned()
  for name in scope.names() {
    if !scope.is_exported(name) {
      continue
    }
    guard scope.get(name) is Some(value) else { continue }
    let mut replaced = false
    for index, entry in result {
      if entry.0 == name {
        result[index] = (name, value.to_string())
        replaced = true
        break
      }
    }
    if !replaced {
      result.push((name, value.to_string()))
    }
  }
  result
}

///|
fn plan_graph_recipe(
  compilation : @semantic.Compilation,
  name : String,
  arguments : Array[@value.Value],
  global : @evaluator.Environment,
  shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  process_environment : ArrayView[(String, String)],
  options : ExecutionOptions,
  ran : Set[String],
  stack : Array[String],
  commands : Array[PlannedCommand],
  stderr : Array[Byte],
) -> Unit raise ExecutionError {
  let key = execution_key(name, arguments)
  if ran.contains(key) {
    return
  }
  if stack.contains(key) {
    raise DependencyCycle(stack=[name, name])
  }
  guard compilation.recipe(name) is Some(recipe) else {
    raise UnknownRecipe(recipe=name)
  }
  let scope = @evaluator.bind_recipe_parameters(recipe, arguments, global) catch {
    error => raise Evaluation(error)
  }
  stack.push(key)
  for dependency in recipe.dependencies() {
    plan_graph_recipe(
      compilation,
      dependency.name(),
      dependency_arguments(dependency, scope),
      global,
      shell,
      cwd,
      process_environment,
      options,
      ran,
      stack,
      commands,
      stderr,
    )
  }
  let recipe_environment = environment_with_exports(process_environment, scope)
  plan_recipe_lines(
    recipe, scope, shell, cwd, recipe_environment, options, commands, stderr,
  )
  let subsequent_ran : Set[String] = Set([])
  for dependency in recipe.subsequent_dependencies() {
    plan_graph_recipe(
      compilation,
      dependency.name(),
      dependency_arguments(dependency, scope),
      global,
      shell,
      cwd,
      process_environment,
      options,
      subsequent_ran,
      [],
      commands,
      stderr,
    )
  }
  ignore(stack.pop())
  ran.add(key)
}

///|
/// Build a complete deterministic process plan without granting process access.
/// Any static/evaluation failure therefore occurs before the first spawn.
pub fn plan_recipe_graph(
  compilation : @semantic.Compilation,
  requests : ArrayView[RecipeRequest],
  global : @evaluator.Environment,
  shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  process_environment? : ArrayView[(String, String)] = [],
  options? : ExecutionOptions = ExecutionOptions::new(),
) -> ExecutionPlan raise ExecutionError {
  let commands : Array[PlannedCommand] = []
  let stderr : Array[Byte] = []
  let ran : Set[String] = Set([])
  for request in requests {
    plan_graph_recipe(
      compilation,
      request.recipe(),
      request.arguments().to_owned(),
      global,
      shell,
      cwd,
      process_environment,
      options,
      ran,
      [],
      commands,
      stderr,
    )
  }
  ExecutionPlan::new(
    commands.map(fn(command) { Command(command, command.echo().to_owned()) }),
    commands,
    Bytes::from_array(stderr),
    options,
  )
}

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
    result.push(
      @evaluator.evaluate_with_async_effects(
        process,
        host,
        expression,
        context,
        effect_shell,
        environment~,
      ) catch {
        error => raise Evaluation(error)
      },
    )
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
] recipe_working_directory(
  process : P,
  host : H,
  attributes : @semantic.RecipeAttributes?,
  environment : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
  fallback : @path.PathValue,
) -> @path.PathValue raise ExecutionError {
  let value = match attributes {
    Some(value) => value
    None => return fallback
  }
  let expression = match value.working_directory() {
    Some(expression) => expression
    None => return fallback
  }
  let text = evaluate_recipe_expression(
    process, host, expression, environment, context, shell,
  ).to_string()
  let path = @path.PathValue::new(text, fallback.flavor()) catch {
    _ => raise Host(InvalidInput("recipe working directory is invalid"))
  }
  fallback.join(path) catch {
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
) -> Array[(String, String)] raise ExecutionError {
  let result = environment_with_exports(base, scope)
  guard attributes is Some(value) else { return result }
  for entry in value.env() {
    let key = evaluate_recipe_expression(
      process,
      host,
      entry.0,
      scope,
      context,
      shell,
    ).to_string()
    let evaluated = evaluate_recipe_expression(
      process,
      host,
      entry.1,
      scope,
      context,
      shell,
    ).to_string()
    let mut replaced = false
    for index, existing in result {
      if existing.0 == key {
        result[index] = (key, evaluated)
        replaced = true
        break
      }
    }
    if !replaced {
      result.push((key, evaluated))
    }
  }
  result
}

///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] plan_graph_recipe_async(
  process : P,
  host : H,
  compilation : @semantic.Compilation,
  name : String,
  arguments : Array[@value.Value],
  global : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  process_environment : ArrayView[(String, String)],
  options : ExecutionOptions,
  configuration : ScriptConfiguration,
  ran : Set[String],
  stack : Array[String],
  steps : Array[PlannedStep],
  commands : Array[PlannedCommand],
  stderr : Array[Byte],
) -> Unit raise ExecutionError {
  let key = execution_key(name, arguments)
  if ran.contains(key) {
    return
  }
  if stack.contains(key) {
    raise DependencyCycle(stack=[name, name])
  }
  guard compilation.recipe(name) is Some(recipe) else {
    raise UnknownRecipe(recipe=name)
  }
  let scope = @evaluator.bind_recipe_parameters_with_async_effects(
    process,
    host,
    recipe,
    arguments,
    global,
    context,
    @evaluator.EffectShell::new(shell.program(), shell.arguments().to_owned()),
  ) catch {
    error => raise Evaluation(error)
  }
  let attributes = compilation.recipe_attributes(name)
  let recipe_shell = recipe_shell(
    process, host, attributes, scope, context, shell,
  )
  let recipe_cwd = recipe_working_directory(
    process, host, attributes, scope, context, recipe_shell, cwd,
  )
  let recipe_context = @evaluator.EvaluationContext::new(
    cwd=recipe_cwd,
    recipe=name,
  )
  let recipe_environment = recipe_process_environment(
    process, host, attributes, scope, recipe_context, recipe_shell, process_environment,
  )
  stack.push(key)
  for dependency in recipe.dependencies() {
    let values = async_dependency_arguments(
      process, host, dependency, scope, recipe_context, recipe_shell,
    )
    if dependency.starred() && values.length() == 1 {
      match values[0] {
        List(elements) =>
          for element in elements {
            plan_graph_recipe_async(
              process,
              host,
              compilation,
              dependency.name(),
              [element],
              global,
              context,
              shell,
              cwd,
              process_environment,
              options,
              configuration,
              ran,
              stack,
              steps,
              commands,
              stderr,
            )
          }
        value =>
          plan_graph_recipe_async(
            process,
            host,
            compilation,
            dependency.name(),
            [value],
            global,
            context,
            shell,
            cwd,
            process_environment,
            options,
            configuration,
            ran,
            stack,
            steps,
            commands,
            stderr,
          )
      }
    } else {
      plan_graph_recipe_async(
        process,
        host,
        compilation,
        dependency.name(),
        values,
        global,
        context,
        shell,
        cwd,
        process_environment,
        options,
        configuration,
        ran,
        stack,
        steps,
        commands,
        stderr,
      )
    }
  }
  let is_script = attributes.map(fn(value) { value.script() }).unwrap_or(false) ||
    compilation.settings().bool("default-script") ||
    recipe_has_shebang(recipe)
  if is_script {
    let extension = match attributes {
      Some(value) => value.extension()
      None => configuration.extension()
    }
    let extension = extension.unwrap_or("")
    let script_configuration = ScriptConfiguration::new(
      configuration.interpreter(),
      configuration.temporary_directory(),
      configuration.platform(),
      extension~,
    )
    let planned = plan_script_recipe_async(
      process,
      host,
      recipe,
      scope,
      recipe_context,
      recipe_shell,
      recipe_cwd,
      script_configuration,
      process_environment=recipe_environment,
      quiet=options.quiet(),
      dry_run=options.dry_run(),
    )
    let script_echo : Array[Byte] = []
    if options.dry_run() ||
      options.verbose() ||
      options.timestamp() is Some(_) ||
      (!options.quiet() && !recipe.quiet()) {
      let script_text = @utf8.decode(planned.contents()) catch { _ => "" }
      for line in script_text.split("\n") {
        if line.is_empty() {
          continue
        }
        append_bytes(
          script_echo,
          render_command_echo(
            line.to_owned(),
            timestamp=options.timestamp(),
            color=options.command_color(),
          )[:],
        )
      }
    }
    if options.dry_run() {
      append_bytes(stderr, Bytes::from_array(script_echo)[:])
    } else {
      steps.push(Script(planned, Bytes::from_array(script_echo)))
    }
  } else {
    for index, source_line in recipe.lines() {
      let planned_line = PlannedLine::new(
        source_line,
        scope,
        recipe_context,
        recipe_shell,
        recipe_cwd,
        recipe_environment,
        options,
        recipe.name(),
        recipe.quiet(),
        index + 1,
      )
      if options.dry_run() {
        let (command, echo) = materialize_line_async(
          process, host, planned_line,
        )
        if !command.spec().arguments().last().unwrap_or("").is_empty() {
          append_bytes(stderr, echo[:])
        }
      } else {
        steps.push(Line(planned_line))
      }
    }
  }
  let subsequent_ran : Set[String] = Set([])
  for dependency in recipe.subsequent_dependencies() {
    let values = async_dependency_arguments(
      process, host, dependency, scope, recipe_context, recipe_shell,
    )
    plan_graph_recipe_async(
      process,
      host,
      compilation,
      dependency.name(),
      values,
      global,
      context,
      shell,
      cwd,
      process_environment,
      options,
      configuration,
      subsequent_ran,
      [],
      steps,
      commands,
      stderr,
    )
  }
  ignore(stack.pop())
  ran.add(key)
}

///|
/// Async planning variant used by the process runtime. Backticks and
/// effectful builtins are evaluated through the same async process adapter.
pub async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] plan_recipe_graph_async(
  process : P,
  host : H,
  compilation : @semantic.Compilation,
  requests : ArrayView[RecipeRequest],
  global : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  configuration : ScriptConfiguration,
  process_environment? : ArrayView[(String, String)] = [],
  options? : ExecutionOptions = ExecutionOptions::new(),
) -> ExecutionPlan raise ExecutionError {
  let steps : Array[PlannedStep] = []
  let commands : Array[PlannedCommand] = []
  let stderr : Array[Byte] = []
  let ran : Set[String] = Set([])
  for request in requests {
    plan_graph_recipe_async(
      process,
      host,
      compilation,
      request.recipe(),
      request.arguments().to_owned(),
      global,
      context,
      shell,
      cwd,
      process_environment,
      options,
      configuration,
      ran,
      [],
      steps,
      commands,
      stderr,
    )
  }
  ExecutionPlan::new(steps, commands, Bytes::from_array(stderr), options)
}
