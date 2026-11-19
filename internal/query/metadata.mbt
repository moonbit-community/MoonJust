///|
type MetadataValues = Map[@source.Span, @value.Value]

///|
/// A module declaration lives in its parent's scope. Recipe attributes live in
/// the recipe's own module. Private and unlisted recipes still have their
/// metadata checked by just's analyzer.
fn evaluate_metadata(
  project : @semantic.ProjectCompilation,
  overrides : Map[@modulepath.ModulePath, Array[(String, String)]],
) -> MetadataValues raise QueryError {
  let expressions : Map[@modulepath.ModulePath, Array[@syntax.Expression]] = Map([],
  )
  fn collect(
    path : @modulepath.ModulePath,
    attributes : ArrayView[@syntax.Attribute],
  ) {
    for attribute in attributes {
      for argument in attribute.arguments() {
        match (attribute.name(), argument.key(), argument.value()) {
          ("doc" | "group", None, Some(expr))
          | ("arg", Some("help" | "pattern"), Some(expr)) =>
            expressions.get_or_init(path, fn() { [] }).push(expr)
          _ => ()
        }
      }
    }
  }
  for path in project.module_paths() {
    if path.parent() is Some(parent) {
      collect(parent, project.module_declaration_attributes(path))
    }
    let compilation = project.module_compilation(path).unwrap()
    for name in compilation.recipe_names() {
      collect(path, compilation.recipe(name).unwrap().attributes())
    }
  }
  let values = Map([])
  for path, required in expressions {
    let env = metadata_environment(project, path, overrides)
    for expression in required {
      values[expression.span()] = env.evaluate_expression(expression) catch {
        error => raise Evaluation(error)
      }
    }
  }
  values
}

///|
/// Attribute expressions use the declaring module's assignments and overrides.
/// Resolve dependencies when an expression reads them, as with const settings.
fn metadata_environment(
  project : @semantic.ProjectCompilation,
  path : @modulepath.ModulePath,
  overrides : Map[@modulepath.ModulePath, Array[(String, String)]],
) -> @evaluator.LazyEnvironment raise QueryError {
  let seed = @evaluator.Environment::new()
  @evaluator.install_constants(
    seed,
    project.source_file(path).map(fn(file) { file.flavor() }).unwrap_or(Unix),
  )
  let env = @evaluator.LazyEnvironment::new(
    project.module_compilation(path).unwrap(),
    environment=seed,
  )
  if overrides.get(path) is Some(entries) {
    env.apply_overrides(entries) catch {
      error => raise Evaluation(error)
    }
  }
  env
}

///|
fn module_recipe_comments(
  graph : @loader.LoadedGraph,
  path : @modulepath.ModulePath,
) -> Map[@source.Span, String] {
  let docs = Map([])
  for file in graph.files() {
    if file.module_path() != path {
      continue
    }
    let items = file.ast().items()
    for i, item in items {
      if item is Recipe(recipe) && i > 0 && items[i - 1] is Comment(text~, ..) {
        let doc = text[1:].trim()
        if !doc.is_empty() {
          docs[recipe.span()] = doc.to_owned()
        }
      }
    }
  }
  docs
}

///|
fn attribute_text_value(
  attribute : @syntax.Attribute,
  values : MetadataValues,
) -> String? {
  guard attribute.arguments().get(0) is Some(argument) &&
    argument.value() is Some(expression) else {
    return None
  }
  let elements = values[expression.span()].elements()
  if elements.is_empty() {
    None
  } else {
    Some(elements.join(" "))
  }
}

///|
fn recipe_metadata_doc(
  recipe : @syntax.Recipe,
  docs : Map[@source.Span, String],
  values : MetadataValues,
) -> String? {
  for attribute in recipe.attributes() {
    if attribute.name() == "doc" {
      guard attribute_text_value(attribute, values) is Some(doc) else {
        return None
      }
      let text = doc.trim()
      return if text.is_empty() { None } else { Some(text.to_owned()) }
    }
  }
  docs.get(recipe.span())
}
