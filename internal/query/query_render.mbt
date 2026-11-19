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
  builder.write_string(
    @formatter.format(
      @syntax.Ast::new(span.source_id(), [Recipe(recipe)], span),
    ),
  )
  builder.to_string()
}

///|
fn usage_recipe_text(
  compilation : @semantic.Compilation,
  requested : String,
  display_path : String,
  environment? : @evaluator.Environment,
) -> String raise QueryError {
  let name = compilation.alias_target(requested).unwrap_or(requested)
  guard compilation.recipe(name) is Some(recipe) else {
    raise Query(unknown_recipe_message(compilation, requested))
  }
  let builder = StringBuilder()
  if name != requested {
    builder.write_string("alias ")
    builder.write_string(requested)
    builder.write_string(" := ")
    builder.write_string(name)
    builder.write_char('\n')
  }
  builder.write_string("Usage: just ")
  builder.write_string(display_path)
  let mut has_options = false
  let mut has_arguments = false
  for parameter in recipe.parameters() {
    let display = parameter_display(recipe, parameter, environment?)
    if display.option {
      has_options = true
    } else {
      has_arguments = true
    }
  }
  if has_options {
    builder.write_string(" [OPTIONS]")
  }
  for parameter in recipe.parameters() {
    if parameter_display(recipe, parameter, environment?).option {
      continue
    }
    builder.write_char(' ')
    let label = parameter.name() +
      (if parameter.variadic() { "..." } else { "" })
    if parameter.default_value() is Some(_) ||
      (parameter.variadic() && parameter.variadic_minimum() == 0) {
      builder.write_string("[" + label + "]")
    } else {
      builder.write_string(label)
    }
  }
  builder.write_string("\n")
  if has_arguments {
    builder.write_string("\nArguments:\n")
    for parameter in recipe.parameters() {
      let display = parameter_display(recipe, parameter, environment?)
      if display.option {
        continue
      }
      builder.write_string("  ")
      let label = parameter.name() +
        (if parameter.variadic() { "..." } else { "" })
      match parameter.default_value() {
        Some(value) =>
          builder.write_string(
            "[" +
            label +
            "] [default: " +
            @formatter.format_expression(value) +
            "]",
          )
        None if parameter.variadic() && parameter.variadic_minimum() == 0 =>
          builder.write_string("[" + label + "]")
        None => builder.write_string(label)
      }
      match display.help {
        Some(help) => builder.write_string(" " + help)
        None => ()
      }
      if !display.pattern.is_empty() {
        builder.write_string(
          " [pattern: '" + display.pattern.join("' | '") + "']",
        )
      }
      builder.write_char('\n')
    }
  }
  if has_options {
    if has_arguments {
      builder.write_string("\nOptions:\n")
    } else {
      builder.write_string("Options:\n")
    }
    for parameter in recipe.parameters() {
      let display = parameter_display(recipe, parameter, environment?)
      if !display.option {
        continue
      }
      builder.write_string("  ")
      match display.short {
        Some(short) => builder.write_string("-" + short)
        None => builder.write_string("  ")
      }
      match display.long {
        Some(long) => {
          if display.short is Some(_) {
            builder.write_string(", ")
          } else {
            builder.write_string("  ")
          }
          builder.write_string("--" + long)
        }
        None => ()
      }
      if !display.value && !display.flag {
        builder.write_string(" " + parameter.name())
      }
      match display.help {
        Some(help) => builder.write_string(" " + help)
        None => ()
      }
      match parameter.default_value() {
        Some(default) if !display.value =>
          builder.write_string(
            " [default: " + @formatter.format_expression(default) + "]",
          )
        _ => ()
      }
      if !display.pattern.is_empty() {
        builder.write_string(
          " [pattern: '" + display.pattern.join("' | '") + "']",
        )
      }
      builder.write_char('\n')
    }
  }
  builder.to_string()
}
