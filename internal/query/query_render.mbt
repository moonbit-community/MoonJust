///|
fn show_doc_comment(
  graph : @loader.LoadedGraph,
  recipe : @syntax.Recipe,
) -> String? {
  if recipe.attributes().any(fn(attribute) { attribute.name() == "doc" }) {
    return None
  }
  let span = recipe.span()
  guard graph
    .files()
    .iter()
    .find_first(fn(file) { file.ast().source_id() == span.source_id() })
    is Some(file) else {
    return None
  }
  let items = file.ast().items()
  for i, item in items {
    if item is Recipe(definition) && definition.span() == span {
      guard i > 0 && items[i - 1] is Comment(text~, ..) else { return None }
      let doc = text[1:].trim()
      return if doc.is_empty() { None } else { Some(doc.to_owned()) }
    }
  }
  None
}

///|
fn show_recipe_text(
  graph : @loader.LoadedGraph,
  project : @semantic.ProjectCompilation,
  path : @modulepath.ModulePath,
  requested : String,
) -> String raise QueryError {
  let compilation = project.module_compilation(path).unwrap()
  guard project.resolve_recipe(path, requested) is Some(resolved) else {
    raise Query(unknown_recipe_message(compilation, requested))
  }
  let recipe = project
    .module_compilation(resolved.module_path())
    .unwrap()
    .recipe(resolved.recipe_name())
    .unwrap()
  let span = recipe.span()
  let builder = StringBuilder()
  if compilation.alias_target(requested) is Some(target) {
    builder.write_string("alias " + requested + " := " + target + "\n")
  }
  if show_doc_comment(graph, recipe) is Some(doc) {
    builder.write_string("# " + doc + "\n")
  }
  // The analyzer displays recipe attributes ordered by kind.
  let attributes = recipe.attributes().to_owned()
  attributes.sort_by(fn(left, right) {
    lexical_compare(left.name(), right.name())
  })
  let shown = { ..recipe, attributes, }
  builder.write_string(
    @formatter.format(@syntax.Ast::new(span.source_id(), [Recipe(shown)], span)),
  )
  builder.to_string()
}

///|
fn usage_recipe_text(
  recipe : @syntax.Recipe,
  display_path : String,
  values : MetadataValues,
  color : Bool,
  in_module~ : Bool,
) -> String {
  let signature = StringBuilder()
  let arguments = []
  let options = []
  for parameter in recipe.parameters() {
    let display = parameter_display(recipe, parameter, values~)
    let line = StringBuilder()
    if display.option {
      match display.short {
        Some(short) => line.write_string(paint("-" + short, "32", color))
        None => line.write_string("  ")
      }
      if display.long is Some(long) {
        line.write_string(if display.short is Some(_) { ", " } else { "  " })
        line.write_string(paint("--" + long, "32", color))
      }
      if !display.value && !display.flag {
        line.write_string(" " + paint(parameter.name(), "36", color))
      }
    } else {
      let optional = parameter.default_value() is Some(_) ||
        (parameter.variadic() && parameter.variadic_minimum() == 0)
      if optional {
        line.write_string(paint("[", "36", color))
      }
      line.write_string(paint(parameter.name(), "36", color))
      if parameter.variadic() {
        line.write_string(paint("...", "36", color))
      }
      if optional {
        line.write_string(paint("]", "36", color))
      }
      signature.write_string(" " + line.to_string())
    }
    if display.help is Some(help) {
      line.write_string(" " + help)
    }
    if !display.value && parameter.default_value() is Some(value) {
      line.write_string(
        " [default: " + @formatter.format_expression(value) + "]",
      )
    }
    if !display.pattern.is_empty() {
      line.write_string(" [pattern: '" + display.pattern.join("' | '") + "']")
    }
    if display.option {
      options.push(line.to_string())
    } else {
      arguments.push(line.to_string())
    }
  }
  let builder = StringBuilder()
  let indentation = if in_module { "    " } else { "" }
  if !in_module {
    builder.write_string(paint("Usage:", "1;33", color) + " ")
  }
  builder.write_string(
    indentation +
    paint("just", "36", color) +
    " " +
    paint(display_path, "36", color),
  )
  if !options.is_empty() {
    builder.write_string(" " + paint("[OPTIONS]", "36", color))
  }
  builder.write_string(signature.to_string())
  builder.write_char('\n')
  for (heading, lines) in [("Arguments:", arguments), ("Options:", options)] {
    if lines.is_empty() {
      continue
    }
    if !in_module {
      builder.write_string("\n" + paint(heading, "1;33", color) + "\n")
    }
    for line in lines {
      builder.write_string(indentation + "  " + line + "\n")
    }
  }
  builder.to_string()
}
