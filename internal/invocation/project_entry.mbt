///|
/// Parse invocations across independently compiled project modules. Both
/// `module::recipe` and the upstream space-separated `module recipe` form are
/// accepted. Existing single-compilation parsing remains unchanged.
pub fn parse_project_invocations(
  project : @semantic.ProjectCompilation,
  arguments : ArrayView[String],
  overrides~ : ArrayView[(String, String)] = [],
  allow_missing~ : Bool = false,
) -> Array[ProjectInvocation] raise InvocationError {
  let environments : Map[@modulepath.ModulePath, @evaluator.Environment] = Map([])
  for path in project.module_paths() {
    let compilation = project.module_compilation(path).unwrap()
    environments[path] = @evaluator.evaluate_compilation(
      compilation,
      overrides=project_overrides(path, overrides),
    ) catch {
      error => raise Evaluation(error)
    }
  }
  resolve_project_invocations(project, arguments, environments~, allow_missing~)
}

///|
/// Resolve and group raw CLI arguments once. Supplying module environments also evaluates defaults and argument constraints.
pub fn resolve_project_invocations(
  project : @semantic.ProjectCompilation,
  arguments : ArrayView[String],
  environments? : Map[@modulepath.ModulePath, @evaluator.Environment],
  allow_missing~ : Bool = false,
) -> Array[ProjectInvocation] raise InvocationError {
  let result : Array[ProjectInvocation] = []
  let mut cursor = 0
  while cursor < arguments.length() || result.is_empty() {
    let resolved = try
      Some(resolve_project_recipe(project, arguments, cursor))
    catch {
      UnknownRecipe(_)
      | UnknownRecipeSuggested(_)
      | UnknownSubmodule(_)
      | OptionalModuleAbsent(_) if allow_missing => None
      error => raise error
    } noraise {
      value => value
    }
    guard resolved is Some((module_path, recipe, path_consumed)) else {
      cursor += 1
      if cursor >= arguments.length() {
        break
      }
      continue
    }
    let compilation = project.module_compilation(module_path).unwrap()
    let (invocation, consumed) = parse_recipe_arguments(
      compilation,
      compilation.recipe(recipe).unwrap(),
      arguments[cursor + path_consumed:],
      environments.map(scopes => scopes[module_path]),
      display_name=arguments[cursor:cursor + path_consumed].join("::"),
    )
    result.push({ module_path, invocation, })
    cursor += path_consumed + consumed
    if cursor >= arguments.length() {
      break
    }
  }
  result
}
