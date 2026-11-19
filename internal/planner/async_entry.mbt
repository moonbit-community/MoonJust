///|
async fn[
  P : @host.HostProcess,
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
  evaluation_directory : @path.PathValue,
  invocation_directory : @path.PathValue,
  process_environment : ArrayView[(String, String)],
  options : ExecutionOptions,
  configuration : ScriptConfiguration,
  ran : Map[String, Int32],
  stack : Array[String],
  entry_dependencies : Array[Int32],
  tasks : Array[ExecutionTask],
  is_dependency : Bool,
  project? : @semantic.ProjectCompilation,
  module_path~ : @modulepath.ModulePath = @modulepath.ModulePath::root(),
  project_runtimes~ : Map[@modulepath.ModulePath, ProjectModuleRuntime] = Map([]),
) -> Int32 raise ExecutionError {
  let key = module_path.as_string() +
    "\u{0000}" +
    execution_key(name, arguments)
  let display_name = if module_path.is_root() {
    name
  } else {
    module_path.as_string() + "::" + name
  }
  match ran.get(key) {
    Some(value) => return value
    None => ()
  }
  if stack.contains(key) {
    raise DependencyCycle(stack=[name, name])
  }
  guard compilation.recipe(name) is Some(recipe) else {
    raise UnknownRecipe(recipe=name)
  }
  @invocation.validate_recipe_argument_values(
    compilation, name, arguments, global,
  ) catch {
    error => raise Invocation(error)
  }
  let attributes = compilation.recipe_attributes(name)

  match
    plan_plain_empty_fanout(
      compilation, recipe, attributes, name, display_name, module_path, entry_dependencies,
      tasks, ran, options,
    ) {
    Some(value) => return value
    None => ()
  }

  // Empty, attribute-free recipes are graph nodes with no evaluation work.
  // Keep their task and dependency edges, but avoid constructing evaluator
  // scopes and host effect shells for every node in a large static DAG.
  let no_dependencies = options.no_dependencies()
  let plain_empty = recipe.parameters().is_empty() &&
    recipe.lines().is_empty() &&
    attributes.map(fn(value) { value.names().is_empty() }).unwrap_or(false) &&
    (no_dependencies || recipe.dependencies().is_empty()) &&
    (no_dependencies || recipe.subsequent_dependencies().is_empty())
  if plain_empty {
    stack.push(key)
    let task_dependencies : Array[Int32] = []
    for dependency in entry_dependencies {
      if !task_dependencies.contains(dependency) {
        task_dependencies.push(dependency)
      }
    }
    let task_id = tasks.length()
    let print_exit_message = !compilation.settings().bool("no-exit-message")
    let preamble = if options.explain() {
      match compilation.recipe_doc(name) {
        Some(doc) => {
          let text = "#### " + doc
          if options.color_enabled() {
            @utf8.encode("\u{001b}[1;36m" + text + "\u{001b}[0m\n")
          } else {
            @utf8.encode(text + "\n")
          }
        }
        None => b""
      }
    } else {
      b""
    }
    tasks.push(
      ExecutionTask::new(
        task_id,
        task_id,
        display_name,
        [],
        task_dependencies,
        print_exit_message~,
        preamble~,
      ),
    )
    ignore(stack.pop())
    ran[key] = task_id
    return task_id
  }
  let definition_context = context.for_source(recipe.span().source_id())
  let continue_signals = planned_continue_signals(attributes)
  let env_attributes = recipe_environment_attributes(
    process, host, attributes, global, definition_context, shell, recipe,
  )
  let base = environment_with_exports(process_environment, global)
  let attribute_environment = with_recipe_env(base, env_attributes)
  let binding_context = definition_context
    .with_process_environment(attribute_environment)
    .for_recipe(evaluation_directory, name, is_dependency)
  let scope = @evaluator.bind_recipe_parameters_with_async_effects(
    process,
    host,
    recipe,
    arguments,
    global,
    binding_context,
    @evaluator.EffectShell::new(shell.program(), shell.arguments().to_owned()),
    allow_empty=empty_option_parameters(attributes),
  ) catch {
    error => raise Evaluation(error)
  }
  let parameter_environment = environment_with_parameter_exports(
    base,
    recipe,
    scope,
    compilation.settings().bool("export"),
  )
  let recipe_environment = with_recipe_env(
    parameter_environment, env_attributes,
  )
  let parameter_context = binding_context.with_process_environment(
    recipe_environment,
  )
  let recipe_shell = recipe_shell(
    process, host, attributes, scope, parameter_context, shell,
  )
  let recipe_cwd = recipe_working_directory(
    process, host, attributes, scope, parameter_context, recipe_shell, evaluation_directory,
    invocation_directory, cwd, recipe,
  )
  let recipe_context = parameter_context
    .for_recipe(recipe_cwd, name, is_dependency)
    .with_process_environment(recipe_environment)
  let entry_dependencies = if !options.assume_yes &&
    attributes is Some(attributes) &&
    attributes.confirm() {
    let expression = attributes.confirm_prompt()
    async fn prompt() -> String raise ExecutionError {
      match expression {
        Some(expression) =>
          confirmation_text(
            evaluate_recipe_expression(
              process, host, expression, scope, recipe_context, recipe_shell,
            ),
          )
        None => "Run recipe `" + display_name + "`?"
      }
    }
    let gate = tasks.length()
    tasks.push(
      ExecutionTask::new(
        gate,
        gate,
        display_name,
        [],
        entry_dependencies,
        confirmation=prompt,
      ),
    )
    [gate]
  } else {
    entry_dependencies
  }
  stack.push(key)
  let parallel = attributes.map(fn(value) { value.parallel() }).unwrap_or(false)
  let dependencies : Array[@syntax.Dependency] = if options.no_dependencies() {
    []
  } else {
    recipe.dependencies().to_owned()
  }
  let (dependency_terminals, serial_fence) = plan_dependency_group_async(
    process, host, dependencies, project, project_runtimes, module_path, compilation,
    global, recipe_context, shell, recipe_shell, cwd, process_environment, options,
    configuration, scope, ran, stack, entry_dependencies, tasks, parallel,
  )
  let module_options = options.with_echo_quiet(
    options.echo_quiet() || compilation.settings().bool("quiet"),
  )
  let recipe_options = match attributes {
    Some(value) if value.no_quiet() => module_options.with_echo_quiet(false)
    _ => module_options
  }
  let print_exit_message = match attributes {
    Some(value) if value.exit_message() => true
    Some(value) if value.no_exit_message() => false
    _ => !compilation.settings().bool("no-exit-message")
  }
  let takes_positional = compilation.settings().bool("positional-arguments") ||
    attributes.map(fn(value) { value.positional_arguments() }).unwrap_or(false)
  let positional = if takes_positional {
    positional_values(recipe, scope)
  } else {
    []
  }
  let command_positional = if takes_positional {
    command_positional_values(recipe.name(), positional)
  } else {
    []
  }
  let dry_echo : Array[Byte] = []
  let task_steps : Array[PlannedStep] = []
  let mut cache : CacheDirective? = None
  let mut deferred_script = None
  let timestamp = match attributes {
    Some({ timestamp: Some(attribute), .. }) => {
      async fn resolve() -> String raise ExecutionError {
        guard attribute.arguments().get(0) is Some(argument) &&
          argument.value() is Some(expression) else {
          return options.timestamp_format
        }
        let value = evaluate_recipe_expression(
          process,
          host,
          expression,
          scope,
          recipe_context,
          recipe_shell,
          dry_run=options.dry_run(),
        )
        match value.as_string() {
          Some(format) => format
          None =>
            raise InvalidAttributeValue(
              message="list value " +
                value.display() +
                " used as a `[timestamp]` attribute",
              span=attribute.span(),
            )
        }
      }
      Some(resolve)
    }
    _ => None
  }
  let timestamped = timestamp is Some(_) || options.timestamp_enabled
  let has_cache = attributes
    .map(fn(value) { value.names().contains("cache") })
    .unwrap_or(false)
  if has_cache &&
    !options.unstable() &&
    !compilation.settings().bool("unstable") {
    raise CachedRecipesUnstable
  }
  let explicit_script = attributes
    .map(fn(value) { value.script() })
    .unwrap_or(false)
  let explicit_shell = attributes
    .map(fn(value) { value.names().contains("shell") })
    .unwrap_or(false)
  let is_script = explicit_script ||
    (
      !explicit_shell &&
      (
        compilation.settings().bool("default-script") ||
        recipe_has_shebang(recipe)
      )
    )
  if is_script {
    async fn prepare() -> (PlannedScript, Bytes, CacheDirective?) raise ExecutionError {
      let script_interpreter = recipe_script_interpreter(
        process,
        host,
        attributes,
        scope,
        recipe_context,
        recipe_shell,
        configuration.interpreter(),
      )
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
            script_interpreter,
            configuration.temporary_directory(),
            configuration.platform(),
            extension~,
          )
        None =>
          ScriptConfiguration::new(
            script_interpreter,
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
        positional~,
        quiet=recipe_options.quiet(),
        dry_run=recipe_options.dry_run(),
        continue_signals~,
      )
      let directive = if has_cache &&
        options.cache_enabled() &&
        !options.dry_run() {
        let dotenv = project_runtimes
          .get(module_path)
          .map(runtime => runtime.dotenv)
          .unwrap_or([])
        let environment = default_cache_environment(
          dotenv, compilation, global, recipe, scope, env_attributes,
        )
        Some(
          planned_cache_directive(
            process,
            host,
            attributes.unwrap(),
            scope,
            recipe_context,
            recipe_shell,
            positional,
            environment,
            planned,
            display_name,
          ),
        )
      } else {
        None
      }
      let script_echo : Array[Byte] = []
      if !recipe_options.quiet() &&
        !recipe_options.echo_quiet() &&
        (
          recipe_options.dry_run() ||
          recipe.quiet() ||
          recipe_options.verbosity() >= 2
        ) {
        let script_text = @utf8.decode(planned.contents()) catch { _ => "" }
        for line in script_text.split("\n") {
          if line.is_empty() {
            continue
          }
          append_bytes(
            script_echo,
            render_command_echo(
              line.to_owned(),
              color=recipe_options.command_color(),
            )[:],
          )
        }
      }
      (planned, Bytes::from_array(script_echo), directive)
    }
    if timestamped {
      // The banner precedes script interpolation and cache lookup, even on a hit.
      deferred_script = Some((name, prepare))
    } else {
      let (planned, echo, directive) = prepare()
      cache = directive
      if recipe_options.dry_run() {
        append_bytes(dry_echo, echo[:])
      } else {
        task_steps.push(Script(planned, echo))
      }
    }
  } else {
    if has_cache {
      raise Host(InvalidInput("cache attributes require a script recipe"))
    }
    let mut index = 0
    while index < recipe.lines().length() {
      let source_line = recipe.lines()[index]
      if compilation.settings().bool("ignore-comments") &&
        recipe_line_is_comment(source_line) {
        index += 1
        continue
      }
      let (source_line, end_index) = combined_recipe_line(recipe.lines(), index)
      let planned_line = PlannedLine::new(
        source_line,
        scope,
        recipe_context,
        recipe_shell,
        recipe_cwd,
        recipe_environment,
        recipe_options,
        // Diagnostics name the recipe within its module, matching just's
        // execution errors. The task and command echoes retain display_name
        // separately so qualified invocations remain visible to users.
        name,
        positional=command_positional,
        recipe.quiet(),
        recipe.lines()[end_index].source_end_line(),
        continue_signals~,
      )
      if recipe_options.dry_run() && !timestamped {
        let (command, echo) = materialize_line_async(
          process,
          host,
          planned_line,
          None,
        )
        if !command.spec().arguments().last().unwrap_or("").is_empty() {
          append_bytes(dry_echo, echo[:])
        }
      } else {
        task_steps.push(Line(planned_line))
      }
      index = end_index + 1
    }
  }
  let task_dependencies = entry_dependencies.copy()
  for dependency in (if parallel { dependency_terminals } else { serial_fence }) {
    if !task_dependencies.contains(dependency) {
      task_dependencies.push(dependency)
    }
  }
  let task_id = tasks.length()
  let explanation = if options.explain() {
    match compilation.recipe_doc(name) {
      Some(doc) => {
        let text = "#### " + doc
        if options.color_enabled() {
          @utf8.encode("\u{001b}[1;36m" + text + "\u{001b}[0m\n")
        } else {
          @utf8.encode(text + "\n")
        }
      }
      None => b""
    }
  } else {
    b""
  }
  let preamble = if dry_echo.is_empty() {
    explanation
  } else {
    explanation + Bytes::from_array(dry_echo)
  }
  tasks.push(
    ExecutionTask::new(
      task_id,
      task_id,
      display_name,
      task_steps,
      task_dependencies,
      cache?,
      timestamp?,
      deferred_script?,
      print_exit_message~,
      preamble~,
    ),
  )
  let subsequent_ran : Map[String, Int32] = Map([])
  let subsequent_dependencies : Array[@syntax.Dependency] = if options.no_dependencies() {
    []
  } else {
    recipe.subsequent_dependencies().to_owned()
  }
  let (subsequent_terminals, subsequent_fence) = plan_dependency_group_async(
    process,
    host,
    subsequent_dependencies,
    project,
    project_runtimes,
    module_path,
    compilation,
    global,
    recipe_context,
    shell,
    recipe_shell,
    cwd,
    process_environment,
    options,
    configuration,
    scope,
    subsequent_ran,
    [],
    [task_id],
    tasks,
    parallel,
  )
  ignore(stack.pop())
  let terminal = if subsequent_terminals.is_empty() {
    task_id
  } else if parallel && subsequent_terminals.length() > 1 {
    let barrier_id = tasks.length()
    tasks.push(
      ExecutionTask::new(
        barrier_id,
        barrier_id,
        display_name,
        [],
        subsequent_terminals,
      ),
    )
    barrier_id
  } else if parallel {
    subsequent_terminals.last().unwrap()
  } else {
    subsequent_fence.last().unwrap_or(task_id)
  }
  ran[key] = terminal
  terminal
}

///|
/// Async planning variant used by the process runtime. Backticks and
/// effectful builtins are evaluated through the same async process adapter.
pub async fn[
  P : @host.HostProcess,
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
  process_environment~ : ArrayView[(String, String)] = [],
  options~ : ExecutionOptions = ExecutionOptions::new(),
  cache_directory? : @path.PathValue,
) -> ExecutionPlan raise ExecutionError {
  let options = options.with_guards(compilation.settings().bool("guards"))
  let steps : Array[PlannedStep] = []
  let commands : Array[PlannedCommand] = []
  let tasks : Array[ExecutionTask] = []
  let ran : Map[String, Int32] = Map([])
  let mut root_fence : Array[Int32] = []
  let evaluation_directory = context.cwd().unwrap_or(cwd)
  let invocation_directory = context
    .invocation_directory_native()
    .unwrap_or(cwd)
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
      evaluation_directory,
      invocation_directory,
      process_environment,
      options,
      configuration,
      ran,
      [],
      root_fence,
      tasks,
      false,
    )
    if root_fence.is_empty() || terminal > root_fence[0] {
      root_fence = [terminal]
    }
  }
  for task in tasks {
    for step in task.steps() {
      steps.push(step)
    }
  }
  ExecutionPlan::new(steps, commands, b"", options, tasks~, cache_directory?)
}

///|
/// Plan roots and dependencies across independently scoped project modules.
pub async fn[
  P : @host.HostProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] plan_project_recipe_graph_async(
  process : P,
  host : H,
  project : @semantic.ProjectCompilation,
  requests : ArrayView[ProjectRecipeRequest],
  runtimes : Map[@modulepath.ModulePath, ProjectModuleRuntime],
  options~ : ExecutionOptions = ExecutionOptions::new(),
  cache_directory? : @path.PathValue,
) -> ExecutionPlan raise ExecutionError {
  let steps : Array[PlannedStep] = []
  let commands : Array[PlannedCommand] = []
  let tasks : Array[ExecutionTask] = []
  let ran : Map[String, Int32] = Map([])
  let mut root_fence : Array[Int32] = []
  for request in requests {
    guard project.module_compilation(request.module_path()) is Some(compilation) else {
      raise UnknownRecipe(recipe=request.recipe())
    }
    guard runtimes.get(request.module_path()) is Some(runtime) else {
      raise UnknownRecipe(recipe=request.recipe())
    }
    let context = runtime.context()
    let cwd = runtime.cwd()
    let terminal = plan_graph_recipe_async(
      process,
      host,
      compilation,
      request.recipe(),
      request.arguments().to_owned(),
      runtime.global(),
      context,
      runtime.shell(),
      cwd,
      context.cwd().unwrap_or(cwd),
      context.invocation_directory_native().unwrap_or(cwd),
      runtime.process_environment(),
      options.with_guards(compilation.settings().bool("guards")),
      runtime.configuration(),
      ran,
      [],
      root_fence,
      tasks,
      false,
      project~,
      module_path=request.module_path(),
      project_runtimes=runtimes,
    )
    if root_fence.is_empty() || terminal > root_fence[0] {
      root_fence = [terminal]
    }
  }
  for task in tasks {
    for step in task.steps() {
      steps.push(step)
    }
  }
  ExecutionPlan::new(steps, commands, b"", options, tasks~, cache_directory?)
}
