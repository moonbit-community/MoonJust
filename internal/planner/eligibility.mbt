///|
fn sync_recipe_has_shebang(recipe : @syntax.Recipe) -> Bool {
  guard recipe.lines().get(0) is Some(line) else { return false }
  guard line.fragments().get(0) is Some(Text(text~, ..)) else { return false }
  text.has_prefix("#!")
}

///|
fn compilation_supports_sync_dry_run(
  compilation : @semantic.Compilation,
) -> Bool {
  let settings = compilation.settings()
  if settings.bool("guards") || settings.bool("default-script") {
    return false
  }
  let mut has_recipe = false
  for recipe_name in compilation.recipe_names() {
    guard compilation.recipe(recipe_name) is Some(recipe) else { return false }
    has_recipe = true
    if !recipe.attributes().is_empty() || sync_recipe_has_shebang(recipe) {
      return false
    }
    for parameter in recipe.parameters() {
      match parameter.default_value() {
        Some(expression) if @evaluator.expression_is_effectful(expression) =>
          return false
        _ => ()
      }
    }
    for dependency in recipe.dependencies() {
      if dependency.arguments().any(@evaluator.expression_is_effectful) {
        return false
      }
    }
    for dependency in recipe.subsequent_dependencies() {
      if dependency.arguments().any(@evaluator.expression_is_effectful) {
        return false
      }
    }
    for line in recipe.lines() {
      for fragment in line.fragments() {
        match fragment {
          Interpolation(expression~, ..) if @evaluator.expression_is_effectful(
              expression,
            ) => return false
          _ => ()
        }
      }
    }
  }
  has_recipe
}

///|
/// Whether a project may use the allocation-light synchronous dry-run
/// planner without changing effect or diagnostic ordering.
pub fn supports_sync_dry_run(project : @semantic.ProjectCompilation) -> Bool {
  guard project.module_paths().length() == 1 else { return false }
  guard project.module_paths().get(0) is Some(path) else { return false }
  guard project.module_compilation(path) is Some(compilation) else {
    return false
  }
  compilation_supports_sync_dry_run(compilation)
}
