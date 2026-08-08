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
fn validate_variable_overrides(
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
) -> Unit raise ApplicationError {
  ignore(variable_overrides(compilation, arguments))
}
