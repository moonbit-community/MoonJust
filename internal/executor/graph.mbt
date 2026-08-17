///|
fn empty_report() -> ExecutionReport {
  ExecutionReport::new(b"", b"", 0)
}

///|
fn merge_reports(
  first : ExecutionReport,
  second : ExecutionReport,
) -> ExecutionReport {
  let stdout : Array[Byte] = []
  let stderr : Array[Byte] = []
  append_bytes(stdout, first.stdout())
  append_bytes(stdout, second.stdout())
  append_bytes(stderr, first.stderr())
  append_bytes(stderr, second.stderr())
  ExecutionReport::new(
    Bytes::from_array(stdout),
    Bytes::from_array(stderr),
    first.commands() + second.commands(),
  )
}

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
fn[T : @host.HostProcess] run_graph_recipe(
  host : T,
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
) -> ExecutionReport raise ExecutionError {
  let key = execution_key(name, arguments)
  if ran.contains(key) {
    return empty_report()
  }
  if stack.contains(key) {
    raise DependencyCycle(stack=[name, name])
  }
  guard compilation.recipe(name) is Some(recipe) else {
    raise UnknownRecipe(recipe=name)
  }
  let scope = @evaluator.bind_recipe_parameters(
    recipe,
    arguments,
    global,
    lists=compilation.settings().bool("lists"),
  ) catch {
    error => raise Evaluation(error)
  }
  stack.push(key)
  let mut report = empty_report()
  for dependency in recipe.dependencies() {
    let values = dependency_arguments(dependency, scope)
    for mapped_values in expanded_dependency_argument_sets(dependency, values) {
      report = merge_reports(
        report,
        run_graph_recipe(
          host,
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
        ),
      )
    }
  }
  report = merge_reports(
    report,
    execute_recipe_lines(
      host,
      recipe,
      scope,
      shell,
      cwd,
      process_environment~,
      options~,
    ),
  )
  let subsequent_ran : Set[String] = Set([])
  for dependency in recipe.subsequent_dependencies() {
    let values = dependency_arguments(dependency, scope)
    for mapped_values in expanded_dependency_argument_sets(dependency, values) {
      report = merge_reports(
        report,
        run_graph_recipe(
          host,
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
        ),
      )
    }
  }
  ignore(stack.pop())
  ran.add(key)
  report
}

///|
/// Execute requested roots and their dependencies in stable source order.
/// Ordinary dependencies share once state by recipe and argument value;
/// subsequent dependencies deliberately use a fresh once set.
pub fn[T : @host.HostProcess] execute_recipe_graph(
  host : T,
  compilation : @semantic.Compilation,
  requests : ArrayView[RecipeRequest],
  global : @evaluator.Environment,
  shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  process_environment? : ArrayView[(String, String)] = [],
  options? : ExecutionOptions = ExecutionOptions::new(),
) -> ExecutionReport raise ExecutionError {
  let ran : Set[String] = Set([])
  let mut report = empty_report()
  for request in requests {
    report = merge_reports(
      report,
      run_graph_recipe(
        host,
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
      ),
    )
  }
  report
}
