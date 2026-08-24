///|
fn recipe_line_is_comment(line : @syntax.RecipeLine) -> Bool {
  match line.fragments().get(0) {
    Some(Text(text~, ..)) => text.has_prefix("#")
    _ => false
  }
}

///|
fn recipe_line_is_continuation(line : @syntax.RecipeLine) -> Bool {
  match line.fragments().last() {
    Some(Text(text~, ..)) => text.has_suffix("\\")
    _ => false
  }
}

///|
fn planned_continue_signals(
  attributes : @semantic.RecipeAttributes?,
) -> Array[@host.SignalKind] {
  guard attributes is Some(value) && value.names().contains("continue") else {
    return []
  }
  if value.continue_signals().is_empty() {
    return [Interrupt]
  }
  value
  .continue_signals()
  .map(fn(signal) {
    match signal {
      "SIGHUP" => Hangup
      "SIGINT" => Interrupt
      "SIGQUIT" => OtherSignal(3)
      _ => OtherSignal(0)
    }
  })
}

///|
fn recipe_attribute_span(
  recipe : @syntax.Recipe,
  name : String,
) -> @source.Span {
  for attribute in recipe.attributes() {
    if attribute.name() == name {
      return attribute.span()
    }
  }
  recipe.span()
}

///|
fn combined_recipe_line(
  lines : ArrayView[@syntax.RecipeLine],
  start : Int,
) -> (@syntax.RecipeLine, Int) {
  let fragments : Array[@syntax.RecipeFragment] = []
  let mut index = start
  while index < lines.length() {
    let source = lines[index]
    let continued = recipe_line_is_continuation(source)
    for fragment_index, fragment in source.fragments() {
      match fragment {
        Text(text~, span~) => {
          let mut combined = if index > start && fragment_index == 0 {
            text.trim_start().to_owned()
          } else {
            text
          }
          if continued && fragment_index == source.fragments().length() - 1 {
            combined = combined
              .view(end_offset=combined.length() - 1)
              .to_owned()
          }
          fragments.push(Text(text=combined, span~))
        }
        _ => fragments.push(fragment)
      }
    }
    if !continued || index + 1 >= lines.length() {
      break
    }
    index += 1
  }
  (@syntax.RecipeLine::new(fragments, lines[start].span()), index)
}

///|
fn plan_recipe_lines(
  recipe : @syntax.Recipe,
  environment : @evaluator.Environment,
  shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  process_environment : ArrayView[(String, String)],
  positional : ArrayView[String],
  options : ExecutionOptions,
  ignore_comments : Bool,
  commands : Array[PlannedCommand],
  stderr : Array[Byte],
  continue_signals : ArrayView[@host.SignalKind],
) -> Unit raise ExecutionError {
  let mut index = 0
  while index < recipe.lines().length() {
    let source_line = recipe.lines()[index]
    if ignore_comments && recipe_line_is_comment(source_line) {
      index += 1
      continue
    }
    let (source_line, end_index) = combined_recipe_line(recipe.lines(), index)
    let line = evaluate_line(source_line, environment)
    if !line.command.is_empty() &&
      (
        options.dry_run() ||
        options.verbose() ||
        options.timestamp() is Some(_) ||
        (
          !options.quiet() &&
          !options.echo_quiet() &&
          !recipe.quiet() &&
          !line.quiet
        )
      ) {
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
            positional~,
          ),
          recipe.name(),
          recipe.lines()[end_index].source_end_line(),
          line.ignore_error,
          continue_signals~,
        ),
      )
    }
    index = end_index + 1
  }
}

///|
fn positional_values(
  recipe : @syntax.Recipe,
  scope : @evaluator.Environment,
) -> Array[String] {
  let positional : Array[String] = []
  for parameter in recipe.parameters() {
    guard scope.get(parameter.name()) is Some(value) else { continue }
    if parameter.variadic() {
      match value {
        String(text) if text.is_empty() => ()
        _ => positional.append(value.elements())
      }
    } else {
      positional.push(value.to_string())
    }
  }
  positional
}

///|
fn command_positional_values(
  recipe : String,
  positional : ArrayView[String],
) -> Array[String] {
  let result = [recipe]
  for value in positional {
    result.push(value)
  }
  result
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
        if value.elements().is_empty() {
          ignore(result.remove(index))
        } else {
          result[index] = (name, value.to_string())
        }
        replaced = true
        break
      }
    }
    if !replaced && !value.elements().is_empty() {
      result.push((name, value.to_string()))
    }
  }
  result
}

///|
fn environment_with_parameter_exports(
  base : ArrayView[(String, String)],
  recipe : @syntax.Recipe,
  scope : @evaluator.Environment,
  export_all : Bool,
) -> Array[(String, String)] {
  let result = base.to_owned()
  for parameter in recipe.parameters() {
    if !export_all && !parameter.exported() {
      continue
    }
    guard scope.get(parameter.name()) is Some(value) else { continue }
    let mut replaced = false
    for index, entry in result {
      if entry.0 == parameter.name() {
        if value.elements().is_empty() {
          ignore(result.remove(index))
        } else {
          result[index] = (parameter.name(), value.to_string())
        }
        replaced = true
        break
      }
    }
    if !replaced && !value.elements().is_empty() {
      result.push((parameter.name(), value.to_string()))
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
  @invocation.validate_recipe_argument_values(
    compilation, name, arguments, global,
  ) catch {
    error => raise Invocation(error)
  }
  let attributes = compilation.recipe_attributes(name)
  let continue_signals = planned_continue_signals(attributes)
  let scope = @evaluator.bind_recipe_parameters(
    recipe,
    arguments,
    global,
    allow_empty=empty_option_parameters(attributes),
    lists=compilation.settings().bool("lists"),
  ) catch {
    error => raise Evaluation(error)
  }
  stack.push(key)
  let dependencies : Array[@syntax.Dependency] = if options.no_dependencies() {
    []
  } else {
    recipe.dependencies().to_owned()
  }
  for dependency in dependencies {
    let values = dependency_arguments(dependency, scope)
    for mapped_values in expanded_dependency_argument_sets(dependency, values) {
      plan_graph_recipe(
        compilation,
        dependency.name(),
        mapped_values,
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
  }
  let recipe_environment = environment_with_parameter_exports(
    process_environment,
    recipe,
    scope,
    compilation.settings().bool("export"),
  )
  let recipe_options = match attributes {
    Some(attributes) if attributes.no_quiet() => options.with_echo_quiet(false)
    _ => options
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
  plan_recipe_lines(
    recipe,
    scope,
    shell,
    cwd,
    recipe_environment,
    command_positional,
    recipe_options,
    compilation.settings().bool("ignore-comments"),
    commands,
    stderr,
    continue_signals,
  )
  let subsequent_ran : Set[String] = Set([])
  let subsequent_dependencies : Array[@syntax.Dependency] = if options.no_dependencies() {
    []
  } else {
    recipe.subsequent_dependencies().to_owned()
  }
  for dependency in subsequent_dependencies {
    let values = dependency_arguments(dependency, scope)
    for mapped_values in expanded_dependency_argument_sets(dependency, values) {
      plan_graph_recipe(
        compilation,
        dependency.name(),
        mapped_values,
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
/// Build the common static fan-out shape without entering the async evaluator.
/// This is deliberately narrow: aliases, mapped arguments, attributes,
/// parameters, recipe lines, and subsequent dependencies all opt out.
fn plan_plain_empty_fanout(
  compilation : @semantic.Compilation,
  recipe : @syntax.Recipe,
  attributes : @semantic.RecipeAttributes?,
  name : String,
  display_name : String,
  module_path : @modulepath.ModulePath,
  entry_dependencies : ArrayView[Int],
  tasks : Array[ExecutionTask],
  ran : Map[String, Int],
  options : ExecutionOptions,
) -> Int? {
  if options.no_dependencies() ||
    options.explain() ||
    !recipe.parameters().is_empty() ||
    !recipe.lines().is_empty() ||
    !recipe.subsequent_dependencies().is_empty() ||
    !attributes.map(fn(value) { value.names().is_empty() }).unwrap_or(false) {
    return None
  }
  let child_names : Array[String] = []
  for dependency in recipe.dependencies() {
    if dependency.starred() ||
      !dependency.arguments().is_empty() ||
      compilation.alias_target(dependency.name()) is Some(_) {
      return None
    }
    guard compilation.recipe(dependency.name()) is Some(child) else {
      return None
    }
    guard compilation.recipe_attributes(dependency.name())
      is Some(child_attributes) else {
      return None
    }
    if !child.parameters().is_empty() ||
      !child.lines().is_empty() ||
      !child.dependencies().is_empty() ||
      !child.subsequent_dependencies().is_empty() ||
      !child_attributes.names().is_empty() {
      return None
    }
    child_names.push(dependency.name())
  }
  if child_names.is_empty() {
    return None
  }
  let module_name = module_path.as_string()
  let print_exit_message = !compilation.settings().bool("no-exit-message")
  let mut fence = entry_dependencies.to_owned()
  for child_name in child_names {
    let key = module_name + "\u{0000}" + execution_key(child_name, [])
    match ran.get(key) {
      Some(value) => {
        fence = [value]
        continue
      }
      None => ()
    }
    let task_id = tasks.length()
    let child_display = if module_path.is_root() {
      child_name
    } else {
      module_name + "::" + child_name
    }
    tasks.push(
      ExecutionTask::new(
        task_id,
        task_id,
        child_display,
        [],
        fence,
        print_exit_message~,
      ),
    )
    ran[key] = task_id
    fence = [task_id]
  }
  let key = module_name + "\u{0000}" + execution_key(name, [])
  let task_id = tasks.length()
  tasks.push(
    ExecutionTask::new(
      task_id,
      task_id,
      display_name,
      [],
      fence,
      print_exit_message~,
    ),
  )
  ran[key] = task_id
  Some(task_id)
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
  display_name : String,
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
  let raw_body = @utf8.decode(script.contents()) catch {
    _ => raise Host(InvalidInput("script cache body must be valid UTF-8"))
  }
  let body_lines : Array[String] = []
  for line in raw_body.split("\n") {
    body_lines.push(line.to_owned())
  }
  while body_lines.get(0) is Some("") {
    ignore(body_lines.remove(0))
  }
  while !body_lines.is_empty() &&
        body_lines.get(body_lines.length() - 1) is Some("") {
    ignore(body_lines.pop())
  }
  let body = body_lines.join("\n")
  let configuration = script.configuration()
  let cache_environment : Array[(String, String)] = []
  for name in scope.names() {
    if scope.is_exported(name) {
      match scope.get(name) {
        Some(value) if !value.elements().is_empty() =>
          cache_environment.push((name, value.to_string()))
        _ => ()
      }
    }
  }
  CacheDirective::new(
    display_name,
    body,
    configuration.interpreter().program(),
    configuration.interpreter().arguments().to_owned(),
    cache_environment,
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
fn empty_option_parameters(
  attributes : @semantic.RecipeAttributes?,
) -> Set[String] {
  let result : Set[String] = Set([])
  guard attributes is Some(attributes) else { return result }
  let mut parameter : String? = None
  for argument in attributes.args() {
    match argument.key() {
      None =>
        match argument.value() {
          Some(String(value)) => parameter = Some(value.cooked())
          _ => parameter = None
        }
      Some("flag") | Some("multiple") =>
        match parameter {
          Some(name) => result.add(name)
          None => ()
        }
      _ => ()
    }
  }
  result
}

///|
priv struct RecipePlanningTarget {
  module_path : @modulepath.ModulePath
  name : String
  compilation : @semantic.Compilation
  runtime : ProjectModuleRuntime?
}

///|
fn project_runtime(
  runtimes : ArrayView[ProjectModuleRuntime],
  path : @modulepath.ModulePath,
) -> ProjectModuleRuntime? {
  for runtime in runtimes {
    if runtime.module_path() == path {
      return Some(runtime)
    }
  }
  None
}

///|
fn dependency_planning_target(
  project : @semantic.ProjectCompilation?,
  runtimes : ArrayView[ProjectModuleRuntime],
  from : @modulepath.ModulePath,
  compilation : @semantic.Compilation,
  requested : String,
) -> RecipePlanningTarget raise ExecutionError {
  match project {
    None => {
      guard compilation.recipe(requested) is Some(_) else {
        raise UnknownRecipe(recipe=requested)
      }
      { module_path: from, name: requested, compilation, runtime: None }
    }
    Some(project) => {
      guard project.resolve_recipe(from, requested) is Some(address) else {
        raise UnknownRecipe(recipe=requested)
      }
      guard project.module_compilation(address.module_path()) is Some(target) else {
        raise UnknownRecipe(recipe=requested)
      }
      guard project_runtime(runtimes, address.module_path()) is Some(runtime) else {
        raise UnknownRecipe(recipe=requested)
      }
      {
        module_path: address.module_path(),
        name: address.recipe_name(),
        compilation: target,
        runtime: Some(runtime),
      }
    }
  }
}

///|
/// Plan one dependency group with the same target/runtime resolution rules for
/// ordinary and subsequent dependencies. Keeping this traversal in one async
/// state machine avoids emitting two copies of the dependency scheduling logic.
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] plan_dependency_group_async(
  process : P,
  host : H,
  dependencies : ArrayView[@syntax.Dependency],
  project : @semantic.ProjectCompilation?,
  project_runtimes : ArrayView[ProjectModuleRuntime],
  module_path : @modulepath.ModulePath,
  compilation : @semantic.Compilation,
  global : @evaluator.Environment,
  recipe_context : @evaluator.EvaluationContext,
  parent_shell : @environment.ShellConfiguration,
  recipe_shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  process_environment : ArrayView[(String, String)],
  options : ExecutionOptions,
  configuration : ScriptConfiguration,
  scope : @evaluator.Environment,
  ran : Map[String, Int],
  stack : Array[String],
  entry_dependencies : ArrayView[Int],
  tasks : Array[ExecutionTask],
  stderr : Array[Byte],
  confirmations : Array[ConfirmationRequest],
  parallel : Bool,
) -> (Array[Int], Array[Int]) raise ExecutionError {
  let terminals : Array[Int] = []
  let mut serial_fence = entry_dependencies.to_owned()
  for dependency in dependencies {
    let target = dependency_planning_target(
      project,
      project_runtimes,
      module_path,
      compilation,
      dependency.name(),
    )
    let target_global = target.runtime
      .map(ProjectModuleRuntime::global)
      .unwrap_or(global)
    let target_context = target.runtime
      .map(ProjectModuleRuntime::context)
      .unwrap_or(recipe_context)
    let target_shell = target.runtime
      .map(ProjectModuleRuntime::shell)
      .unwrap_or(parent_shell)
    let target_cwd = target.runtime
      .map(ProjectModuleRuntime::cwd)
      .unwrap_or(cwd)
    let target_evaluation_directory = target_context.cwd().unwrap_or(target_cwd)
    let target_invocation_directory = target_context
      .invocation_directory_native()
      .unwrap_or(target_cwd)
    let target_environment = target.runtime
      .map(ProjectModuleRuntime::process_environment)
      .unwrap_or(process_environment)
    let target_configuration = target.runtime
      .map(ProjectModuleRuntime::configuration)
      .unwrap_or(configuration)
    let target_options = options.with_guards(
      target.compilation.settings().bool("guards"),
    )
    // Empty dependency arguments are common in large static DAGs. Avoid
    // constructing an effect shell and evaluating an empty expression list.
    let values = if dependency.arguments().is_empty() {
      []
    } else {
      async_dependency_arguments(
        process, host, dependency, scope, recipe_context, recipe_shell,
      )
    }
    if !dependency.starred() {
      let terminal = plan_graph_recipe_async(
        process,
        host,
        target.compilation,
        target.name,
        values,
        target_global,
        target_context,
        target_shell,
        target_cwd,
        target_evaluation_directory,
        target_invocation_directory,
        target_environment,
        target_options,
        target_configuration,
        ran,
        stack,
        if parallel {
          entry_dependencies.to_owned()
        } else {
          serial_fence.copy()
        },
        tasks,
        stderr,
        confirmations,
        true,
        project?,
        module_path=target.module_path,
        project_runtimes~,
      )
      if !terminals.contains(terminal) {
        terminals.push(terminal)
      }
      if !parallel {
        serial_fence = [terminal]
      }
    } else {
      for mapped_values in expanded_dependency_argument_sets(dependency, values) {
        let terminal = plan_graph_recipe_async(
          process,
          host,
          target.compilation,
          target.name,
          mapped_values,
          target_global,
          target_context,
          target_shell,
          target_cwd,
          target_evaluation_directory,
          target_invocation_directory,
          target_environment,
          target_options,
          target_configuration,
          ran,
          stack,
          if parallel {
            entry_dependencies.to_owned()
          } else {
            serial_fence.copy()
          },
          tasks,
          stderr,
          confirmations,
          true,
          project?,
          module_path=target.module_path,
          project_runtimes~,
        )
        if !terminals.contains(terminal) {
          terminals.push(terminal)
        }
        if !parallel {
          serial_fence = [terminal]
        }
      }
    }
  }
  (terminals, serial_fence)
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
  evaluation_directory : @path.PathValue,
  invocation_directory : @path.PathValue,
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
  project? : @semantic.ProjectCompilation,
  module_path? : @modulepath.ModulePath = @modulepath.ModulePath::root(),
  project_runtimes? : ArrayView[ProjectModuleRuntime] = [],
) -> Int raise ExecutionError {
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
    let task_dependencies : Array[Int] = []
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
  let attribute_environment = recipe_process_environment(
    process, host, attributes, global, definition_context, shell, process_environment,
    recipe,
  )
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
  let recipe_environment = environment_with_parameter_exports(
    attribute_environment,
    recipe,
    scope,
    compilation.settings().bool("export"),
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
        None => "Run recipe `" + display_name + "`?"
      }
      confirmations.push(
        ConfirmationRequest::new(display_name, prompt, is_dependency),
      )
    }
    _ => ()
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
    configuration, scope, ran, stack, entry_dependencies, tasks, stderr, confirmations,
    parallel,
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
  let task_steps : Array[PlannedStep] = []
  let mut cache : CacheDirective? = None
  let has_cache = attributes
    .map(fn(value) { value.names().contains("cache") })
    .unwrap_or(false)
  if has_cache && !options.unstable() {
    raise InvalidAttributeValue(
      message="cached recipes are currently unstable; pass `--unstable`",
      span=recipe.span(),
    )
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
          display_name,
        ),
      )
    }
    let script_echo : Array[Byte] = []
    if recipe_options.timestamp() is Some(_) && !recipe_options.dry_run() {
      append_bytes(
        script_echo,
        render_command_echo(
          display_name,
          timestamp=recipe_options.timestamp(),
          color=recipe_options.command_color(),
        )[:],
      )
    } else if !recipe_options.quiet() &&
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
            timestamp=recipe_options.timestamp(),
            color=recipe_options.command_color(),
          )[:],
        )
      }
    }
    if recipe_options.dry_run() {
      append_bytes(stderr, Bytes::from_array(script_echo)[:])
    } else {
      task_steps.push(Script(planned, Bytes::from_array(script_echo)))
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
        display_name,
        positional=command_positional,
        recipe.quiet(),
        recipe.lines()[end_index].source_end_line(),
        continue_signals~,
      )
      if recipe_options.dry_run() {
        let (command, echo) = materialize_line_async(
          process, host, planned_line,
        )
        if !command.spec().arguments().last().unwrap_or("").is_empty() {
          append_bytes(stderr, echo[:])
        }
      } else {
        task_steps.push(Line(planned_line))
      }
      index = end_index + 1
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
    match cache {
      Some(value) =>
        ExecutionTask::new(
          task_id,
          task_id,
          display_name,
          task_steps,
          task_dependencies,
          cache=value,
          print_exit_message~,
          preamble~,
        )
      None =>
        ExecutionTask::new(
          task_id,
          task_id,
          display_name,
          task_steps,
          task_dependencies,
          print_exit_message~,
          preamble~,
        )
    },
  )
  let subsequent_ran : Map[String, Int] = Map([])
  let subsequent_dependencies : Array[@syntax.Dependency] = if options.no_dependencies() {
    []
  } else {
    recipe.subsequent_dependencies().to_owned()
  }
  let (subsequent_terminals, _) = plan_dependency_group_async(
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
    stderr,
    confirmations,
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
  let options = options.with_guards(compilation.settings().bool("guards"))
  let steps : Array[PlannedStep] = []
  let commands : Array[PlannedCommand] = []
  let stderr : Array[Byte] = []
  let tasks : Array[ExecutionTask] = []
  let confirmations : Array[ConfirmationRequest] = []
  let ran : Map[String, Int] = Map([])
  let mut root_fence : Array[Int] = []
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

///|
/// Plan roots and dependencies across independently scoped project modules.
pub async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] plan_project_recipe_graph_async(
  process : P,
  host : H,
  project : @semantic.ProjectCompilation,
  requests : ArrayView[ProjectRecipeRequest],
  runtimes : ArrayView[ProjectModuleRuntime],
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
    guard project.module_compilation(request.module_path()) is Some(compilation) else {
      raise UnknownRecipe(recipe=request.recipe())
    }
    guard project_runtime(runtimes, request.module_path()) is Some(runtime) else {
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
      stderr,
      confirmations,
      false,
      project~,
      module_path=request.module_path(),
      project_runtimes=runtimes,
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
