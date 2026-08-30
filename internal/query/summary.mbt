///|
pub fn visible_recipe_names(
  compilation : @semantic.Compilation,
  request : QueryRequest,
) -> Array[String] {
  let arguments = request.arguments()
  let result : Array[String] = []
  let requested_groups = arguments.values("group")
  for name in compilation.recipe_names() {
    match compilation.recipe_attributes(name) {
      Some(attributes) if !name.has_prefix("_") &&
        !attributes.private() &&
        (
          requested_groups.is_empty() ||
          requested_groups.any(fn(group) { attributes.groups().contains(group) })
        ) => result.push(name)
      _ => ()
    }
  }
  if !arguments.flag("unsorted") {
    result.sort_by(lexical_compare)
  }
  result
}

///|
/// Render the common single-source summary without semantic compilation. This
/// is a query-stage decision, not an application or loader special case.
pub fn try_fast_summary(
  graph : @loader.LoadedGraph,
  request : QueryRequest,
) -> QueryResult? {
  let arguments = request.arguments()
  if arguments.command() != SummaryCommand ||
    !arguments.variable_overrides().is_empty() ||
    !arguments.values("group").is_empty() {
    return None
  }
  match arguments.value("color") {
    None | Some("auto") | Some("always") | Some("never") => ()
    Some(_) => return None
  }
  guard graph.files().length() == 1 else { return None }
  let loaded = graph.files()[0]
  if loaded.relation() != RootSource || !loaded.module_path().is_root() {
    return None
  }
  let names : Array[String] = []
  let seen : Set[String] = Set([])
  for item in loaded.ast().items() {
    match item {
      Recipe(recipe) if recipe.attributes().is_empty() &&
        recipe.parameters().is_empty() &&
        recipe.dependencies().is_empty() &&
        recipe.subsequent_dependencies().is_empty() &&
        recipe.lines().is_empty() => {
        if seen.contains(recipe.name()) {
          return None
        }
        seen.add(recipe.name())
        if !recipe.name().has_prefix("_") {
          names.push(recipe.name())
        }
      }
      Blank(_) | Comment(_) | TrailingComment(_) => ()
      _ => return None
    }
  }
  if !arguments.flag("unsorted") {
    names.sort_by(lexical_compare)
  }
  let output = names.join(" ") + "\n"
  let stderr = if !arguments.flag("quiet") && output == "\n" {
    b"justfile contains no recipes\n"
  } else {
    b""
  }
  Some(QueryResult::new(stdout=@utf8.encode(output), stderr~))
}
