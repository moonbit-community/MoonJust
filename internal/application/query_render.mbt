///|
fn show_recipe_text(
  loaded : @loader.LoadedSource,
  compilation : @semantic.Compilation,
  requested : String,
) -> String raise ApplicationError {
  let name = compilation.alias_target(requested).unwrap_or(requested)
  guard compilation.recipe(name) is Some(recipe) else {
    raise Query(unknown_recipe_message(compilation, requested))
  }
  let items : Array[@syntax.Item] = []
  if name != requested {
    for item in loaded.ast().items() {
      if item is Alias(definition) && definition.name() == requested {
        items.push(item)
        break
      }
    }
  }
  let mut comments : Array[@syntax.Item] = []
  for item in loaded.ast().items() {
    match item {
      Comment(_) => comments.push(item)
      Recipe(value) if value.name() == name => {
        if !value.attributes().any(fn(attribute) { attribute.name() == "doc" }) {
          items.append(comments)
        }
        items.push(Recipe(recipe))
        break
      }
      Attribute(_) => comments = []
      _ => comments = []
    }
  }
  @formatter.format(
    @syntax.Ast::new(compilation.source_id(), items, recipe.span()),
  )
}

///|
fn show_text(
  loaded : @loader.LoadedSource,
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
) -> String raise ApplicationError {
  if arguments.positional().length() > 1 {
    raise Query(
      "`--show` used with unexpected argument: `" +
      arguments.positional()[1] +
      "`",
    )
  }
  guard arguments.positional().get(0) is Some(requested) else {
    raise Query("`--show` requires recipe")
  }
  show_recipe_text(loaded, compilation, requested)
}

///|
fn usage_recipe_text(
  compilation : @semantic.Compilation,
  requested : String,
  display_path : String,
  environment? : @evaluator.Environment,
) -> String raise ApplicationError {
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

///|
fn usage_text(
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
) -> String raise ApplicationError {
  if arguments.positional().length() > 1 {
    raise Query(
      "`--usage` used with unexpected argument: `" +
      arguments.positional()[1] +
      "`",
    )
  }
  guard arguments.positional().get(0) is Some(requested) else {
    raise Query("`--usage` requires recipe")
  }
  usage_recipe_text(compilation, requested, requested)
}
