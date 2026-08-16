///|
/// Validate CLI overrides for query paths that do not otherwise evaluate the
/// assignment environment. Values remain confined to the evaluator and never
/// enter an application diagnostic.
fn variable_overrides(
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
) -> Array[(String, String)] raise ApplicationError {
  if arguments.variable_overrides().is_empty() {
    return []
  }
  let table = @environment.OverrideTable::from_entries(
    arguments.variable_overrides(),
  ) catch {
    error => raise Environment(error)
  }
  let overrides = table
    .entries()
    .map(fn(entry) { (entry.path(), entry.value()) })
  let environment = @evaluator.LazyEnvironment::new(compilation)
  environment.apply_overrides(overrides) catch {
    error => raise Evaluation(error)
  }
  overrides
}

///|
fn project_variable_overrides(
  project : @semantic.ProjectCompilation,
  path : @modulepath.ModulePath,
  arguments : @cli.CliArguments,
) -> Array[(String, String)] raise ApplicationError {
  if arguments.variable_overrides().is_empty() {
    return []
  }
  let entries : Array[(String, String)] = []
  for entry in arguments.variable_overrides() {
    let full = @modulepath.ModulePath::parse(entry.0) catch {
      _ => raise Query("invalid override path `" + entry.0 + "`")
    }
    let components = full.components().to_owned()
    guard components.pop() is Some(name) else { continue }
    let requested_module = components.join("::")
    let resolved = if requested_module.is_empty() {
      Some(@modulepath.ModulePath::root())
    } else {
      project.resolve_module(@modulepath.ModulePath::root(), requested_module)
    }
    if resolved == Some(path) {
      entries.push((name, entry.1))
    }
  }
  let table = @environment.OverrideTable::from_entries(entries) catch {
    error => raise Environment(error)
  }
  let overrides = table
    .entries()
    .map(fn(entry) { (entry.path(), entry.value()) })
  let compilation = project.module_compilation(path).unwrap()
  let environment = @evaluator.LazyEnvironment::new(compilation)
  environment.apply_overrides(overrides) catch {
    error => raise Evaluation(error)
  }
  overrides
}

///|
fn validate_project_variable_overrides(
  project : @semantic.ProjectCompilation,
  arguments : @cli.CliArguments,
) -> Unit raise ApplicationError {
  let unknown : Array[String] = []
  for entry in arguments.variable_overrides() {
    let full = @modulepath.ModulePath::parse(entry.0) catch {
      _ => raise Query("invalid override path `" + entry.0 + "`")
    }
    let components = full.components().to_owned()
    guard components.pop() is Some(name) else { continue }
    let requested_module = components.join("::")
    let path = if requested_module.is_empty() {
      Some(@modulepath.ModulePath::root())
    } else {
      project.resolve_module(@modulepath.ModulePath::root(), requested_module)
    }
    let present = match path {
      Some(path) =>
        project
        .module_compilation(path)
        .map(fn(compilation) { compilation.variable(name) is Some(_) })
        .unwrap_or(false)
      None => false
    }
    if !present && !unknown.contains(entry.0) {
      unknown.push(entry.0)
    }
  }
  if !unknown.is_empty() {
    unknown.sort()
    raise Query(
      (if unknown.length() == 1 { "variable " } else { "variables " }) +
      unknown.map(fn(name) { "`" + name + "`" }).join(" and ") +
      " overridden on the command line but not present in justfile",
    )
  }
}
