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
] planned_cache_directive(
  process : P,
  host : H,
  attributes : @semantic.RecipeAttributes,
  scope : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
  arguments : ArrayView[@value.Value],
  script : PlannedScript,
) -> CacheDirective raise ExecutionError {
  let seen : Set[String] = Set([])
  let mut extra = ""
  let inputs : Array[String] = []
  let outputs : Array[String] = []
  for argument in attributes.cache() {
    guard argument.key() is Some(key) else {
      raise Host(InvalidInput("cache arguments must be named"))
    }
    if seen.contains(key) {
      raise Host(InvalidInput("duplicate cache argument `\{key}`"))
    }
    seen.add(key)
    guard argument.value() is Some(expression) else {
      raise Host(InvalidInput("cache argument `\{key}` requires a value"))
    }
    let value = evaluate_recipe_expression(
      process, host, expression, scope, context, shell,
    )
    match key {
      "extra" => extra = value.to_string()
      "inputs" | "outputs" => {
        let target = if key == "inputs" { inputs } else { outputs }
        match value {
          List(elements) =>
            for element in elements {
              target.push(element.to_string())
            }
          value => target.push(value.to_string())
        }
      }
      _ => raise Host(InvalidInput("unknown cache argument `\{key}`"))
    }
  }
  for path in inputs {
    @cache.validate_relative_path(path) catch {
      _ => raise Host(InvalidInput("invalid cache input path `\{path}`"))
    }
  }
  for path in outputs {
    @cache.validate_relative_path(path) catch {
      _ => raise Host(InvalidInput("invalid cache output path `\{path}`"))
    }
  }
  let body = @utf8.decode(script.contents()) catch {
    _ => raise Host(InvalidInput("script cache body must be valid UTF-8"))
  }
  let configuration = script.configuration()
  CacheDirective::new(
    script.recipe(),
    body,
    configuration.interpreter().program(),
    configuration.interpreter().arguments().to_owned(),
    script.environment().to_owned(),
    configuration.extension().unwrap_or(""),
    script.cwd(),
    arguments.map(fn(value) { value.to_string() }),
    extra,
    inputs,
    outputs,
  )
}

///|
fn confirmation_text(value : @value.Value) -> String {
  match value {
    List(elements) =>
      elements.map(fn(element) { element.to_string() }).join(" ")
    _ => value.to_string()
  }
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
  ran : Map[String, Int],
  stack : Array[String],
  entry_dependencies : Array[Int],
  tasks : Array[ExecutionTask],
  stderr : Array[Byte],
  confirmations : Array[ConfirmationRequest],
  is_dependency : Bool,
) -> Int raise ExecutionError {
  let key = execution_key(name, arguments)
  guard ran.get(key) is None else { return ran.get(key).unwrap() }
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
    is_dependency~,
    color_mode=context.color_mode().unwrap_or("auto"),
  )
  let recipe_environment = recipe_process_environment(
    process, host, attributes, scope, recipe_context, recipe_shell, process_environment,
  )
  match attributes {
    Some(value) if value.confirm() => {
      let prompt = match value.confirm_prompt() {
        Some(expression) =>
          confirmation_text(
            @evaluator.evaluate_with_async_effects(
              process,
              host,
              expression,
              recipe_context,
              @evaluator.EffectShell::new(
                recipe_shell.program(),
                recipe_shell.arguments().to_owned(),
              ),
              environment=scope,
            ) catch {
              error => raise Evaluation(error)
            },
          )
        None => "Run recipe `" + name + "`?"
      }
      confirmations.push(ConfirmationRequest::new(name, prompt, is_dependency))
    }
    _ => ()
  }
  stack.push(key)
  let parallel = attributes.map(fn(value) { value.parallel() }).unwrap_or(false)
  let dependency_terminals : Array[Int] = []
  let mut serial_fence = entry_dependencies.copy()
  for dependency in recipe.dependencies() {
    let values = async_dependency_arguments(
      process, host, dependency, scope, recipe_context, recipe_shell,
    )
    if dependency.starred() && values.length() == 1 {
      match values[0] {
        List(elements) =>
          for element in elements {
            let terminal = plan_graph_recipe_async(
              process,
              host,
              compilation,
              dependency.name(),
              [element],
              global,
              recipe_context,
              shell,
              cwd,
              process_environment,
              options,
              configuration,
              ran,
              stack,
              if parallel {
                entry_dependencies.copy()
              } else {
                serial_fence.copy()
              },
              tasks,
              stderr,
              confirmations,
              true,
            )
            if !dependency_terminals.contains(terminal) {
              dependency_terminals.push(terminal)
            }
            if !parallel {
              serial_fence = [terminal]
            }
          }
        value => {
          let terminal = plan_graph_recipe_async(
            process,
            host,
            compilation,
            dependency.name(),
            [value],
            global,
            recipe_context,
            shell,
            cwd,
            process_environment,
            options,
            configuration,
            ran,
            stack,
            if parallel {
              entry_dependencies.copy()
            } else {
              serial_fence.copy()
            },
            tasks,
            stderr,
            confirmations,
            true,
          )
          if !dependency_terminals.contains(terminal) {
            dependency_terminals.push(terminal)
          }
          if !parallel {
            serial_fence = [terminal]
          }
        }
      }
    } else {
      let terminal = plan_graph_recipe_async(
        process,
        host,
        compilation,
        dependency.name(),
        values,
        global,
        recipe_context,
        shell,
        cwd,
        process_environment,
        options,
        configuration,
        ran,
        stack,
        if parallel {
          entry_dependencies.copy()
        } else {
          serial_fence.copy()
        },
        tasks,
        stderr,
        confirmations,
        true,
      )
      if !dependency_terminals.contains(terminal) {
        dependency_terminals.push(terminal)
      }
      if !parallel {
        serial_fence = [terminal]
      }
    }
  }
  let task_steps : Array[PlannedStep] = []
  let mut cache : CacheDirective? = None
  let has_cache = attributes
    .map(fn(value) { value.names().contains("cache") })
    .unwrap_or(false)
  if has_cache && !options.unstable() {
    raise Host(
      InvalidInput("cached recipes are currently unstable; pass `--unstable`"),
    )
  }
  let is_script = attributes.map(fn(value) { value.script() }).unwrap_or(false) ||
    compilation.settings().bool("default-script") ||
    recipe_has_shebang(recipe)
  if is_script {
    let extension = match attributes {
      Some(value) =>
        match value.extension() {
          Some(extension) => Some(extension)
          None => configuration.extension()
        }
      None => configuration.extension()
    }
    let script_configuration = match extension {
      Some(extension) =>
        ScriptConfiguration::new(
          configuration.interpreter(),
          configuration.temporary_directory(),
          configuration.platform(),
          extension~,
        )
      None =>
        ScriptConfiguration::new(
          configuration.interpreter(),
          configuration.temporary_directory(),
          configuration.platform(),
        )
    }
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
    if has_cache {
      cache = Some(
        planned_cache_directive(
          process,
          host,
          attributes.unwrap(),
          scope,
          recipe_context,
          recipe_shell,
          arguments,
          planned,
        ),
      )
    }
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
      task_steps.push(Script(planned, Bytes::from_array(script_echo)))
    }
  } else {
    if has_cache {
      raise Host(InvalidInput("cache attributes require a script recipe"))
    }
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
        task_steps.push(Line(planned_line))
      }
    }
  }
  let task_dependencies : Array[Int] = []
  let selected_dependencies = if dependency_terminals.is_empty() {
    entry_dependencies
  } else if parallel {
    dependency_terminals
  } else {
    serial_fence
  }
  for dependency in selected_dependencies {
    if !task_dependencies.contains(dependency) {
      task_dependencies.push(dependency)
    }
  }
  let task_id = tasks.length()
  tasks.push(
    match cache {
      Some(value) =>
        ExecutionTask::new(
          task_id,
          task_id,
          name,
          task_steps,
          task_dependencies,
          cache=value,
        )
      None =>
        ExecutionTask::new(
          task_id, task_id, name, task_steps, task_dependencies,
        )
    },
  )
  let subsequent_ran : Map[String, Int] = Map([])
  let subsequent_terminals : Array[Int] = []
  let mut subsequent_fence = [task_id]
  for dependency in recipe.subsequent_dependencies() {
    let values = async_dependency_arguments(
      process, host, dependency, scope, recipe_context, recipe_shell,
    )
    let terminal = plan_graph_recipe_async(
      process,
      host,
      compilation,
      dependency.name(),
      values,
      global,
      recipe_context,
      shell,
      cwd,
      process_environment,
      options,
      configuration,
      subsequent_ran,
      [],
      if parallel {
        [task_id]
      } else {
        subsequent_fence.copy()
      },
      tasks,
      stderr,
      confirmations,
      true,
    )
    if !subsequent_terminals.contains(terminal) {
      subsequent_terminals.push(terminal)
    }
    if !parallel {
      subsequent_fence = [terminal]
    }
  }
  ignore(stack.pop())
  let terminal = if subsequent_terminals.is_empty() {
    task_id
  } else if parallel && subsequent_terminals.length() > 1 {
    let barrier_id = tasks.length()
    tasks.push(
      ExecutionTask::new(barrier_id, barrier_id, name, [], subsequent_terminals),
    )
    barrier_id
  } else {
    subsequent_terminals.last().unwrap()
  }
  ran[key] = terminal
  terminal
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
  cache_directory? : @path.PathValue,
) -> ExecutionPlan raise ExecutionError {
  let steps : Array[PlannedStep] = []
  let commands : Array[PlannedCommand] = []
  let stderr : Array[Byte] = []
  let tasks : Array[ExecutionTask] = []
  let confirmations : Array[ConfirmationRequest] = []
  let ran : Map[String, Int] = Map([])
  let mut root_fence : Array[Int] = []
  for request in requests {
    let terminal = plan_graph_recipe_async(
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
      root_fence,
      tasks,
      stderr,
      confirmations,
      false,
    )
    root_fence = [terminal]
  }
  for task in tasks {
    for step in task.steps() {
      steps.push(step)
    }
  }
  match cache_directory {
    Some(value) =>
      ExecutionPlan::new(
        steps,
        commands,
        Bytes::from_array(stderr),
        options,
        tasks~,
        cache_directory=value,
        confirmations~,
      )
    None =>
      ExecutionPlan::new(
        steps,
        commands,
        Bytes::from_array(stderr),
        options,
        tasks~,
        confirmations~,
      )
  }
}
