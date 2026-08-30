///|
fn execution_key(name : String, arguments : ArrayView[@value.Value]) -> String {
  let builder = StringBuilder()
  builder.write_string(name.length().to_string())
  builder.write_char(':')
  builder.write_string(name)
  for argument in arguments {
    let text = argument.to_string()
    builder.write_char('|')
    builder.write_string(text.length().to_string())
    builder.write_char(':')
    builder.write_string(text)
  }
  builder.to_string()
}

///|
fn dependency_arguments(
  dependency : @syntax.Dependency,
  environment : @evaluator.Environment,
) -> Array[@value.Value] raise ExecutionError {
  let result : Array[@value.Value] = []
  for expression in dependency.arguments() {
    result.push(
      @evaluator.evaluate(expression, environment~) catch {
        error => raise Evaluation(error)
      },
    )
  }
  result
}

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
  let attributes = compilation.recipe_attributes(name)
  if arguments.is_empty() && options.dry_run() && !options.explain() {
    match
      plain_empty_fanout_children(compilation, recipe, attributes, options) {
      Some(children) => {
        for child in children {
          ran.add(execution_key(child, []))
        }
        ran.add(key)
        return
      }
      None => ()
    }
  }
  @invocation.validate_recipe_argument_values(
    compilation, name, arguments, global,
  ) catch {
    error => raise Invocation(error)
  }
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
