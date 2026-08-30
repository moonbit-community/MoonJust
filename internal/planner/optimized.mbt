///|
fn plain_empty_fanout_children(
  compilation : @semantic.Compilation,
  recipe : @syntax.Recipe,
  attributes : @semantic.RecipeAttributes?,
  options : ExecutionOptions,
) -> Array[String]? {
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
  Some(child_names)
}

///|
/// Build the common static fan-out shape without entering the async evaluator.
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
  retain_tasks? : Bool = true,
) -> Int? {
  guard plain_empty_fanout_children(compilation, recipe, attributes, options)
    is Some(child_names) else {
    return None
  }
  let module_name = module_path.as_string()
  if !retain_tasks {
    for child_name in child_names {
      let key = module_name + "\u{0000}" + execution_key(child_name, [])
      ran[key] = 0
    }
    let key = module_name + "\u{0000}" + execution_key(name, [])
    ran[key] = 0
    return Some(0)
  }
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
      { module_path: from, name: requested, compilation, runtime: None, }
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
