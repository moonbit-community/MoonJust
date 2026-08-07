///|
fn compile_loaded(
  loaded : @loader.LoadedSource,
) -> @semantic.Compilation raise ApplicationError {
  @semantic.compile(loaded.ast()) catch {
    error => raise Semantic(error)
  }
}

///|
fn recipe_docs(ast : @syntax.Ast) -> Map[String, String] {
  let docs : Map[String, String] = Map([])
  let mut pending : Array[String] = []
  for item in ast.items() {
    match item {
      Comment(text~, ..) => {
        let text = text.trim()
        if text.has_prefix("# ") {
          pending.push(text.view(start_offset=2).to_owned())
        } else {
          pending = []
        }
      }
      Blank(_) => pending = []
      Recipe(recipe) => {
        if !pending.is_empty() {
          docs[recipe.name()] = pending.join(" ")
        }
        pending = []
      }
      Attribute(_) => ()
      _ => pending = []
    }
  }
  docs
}

///|
fn recipe_signature(recipe : @syntax.Recipe) -> String {
  let values : Array[String] = [recipe.name()]
  for parameter in recipe.parameters() {
    let prefix = if parameter.variadic() {
      if parameter.variadic_minimum() == 0 {
        "*"
      } else {
        "+"
      }
    } else {
      ""
    }
    let suffix = if parameter.default_value() is Some(_) { "=..." } else { "" }
    values.push(prefix + parameter.name() + suffix)
  }
  values.join(" ")
}

///|
fn lexical_compare(left : String, right : String) -> Int {
  right.compare(left)
}

///|
fn visible_recipe_names(
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
) -> Array[String] {
  let result : Array[String] = []
  let group = arguments.value("group")
  for name in compilation.recipe_names() {
    match compilation.recipe_attributes(name) {
      Some(attributes) if !attributes.private() &&
        (group is None || attributes.group() == group) => result.push(name)
      _ => ()
    }
  }
  if !arguments.flag("unsorted") {
    result.sort_by(lexical_compare)
  }
  result
}

///|
fn alias_names(
  compilation : @semantic.Compilation,
  target : String,
) -> Array[String] {
  let result : Array[String] = []
  for symbol in compilation.symbols() {
    if symbol.kind() is Alias &&
      compilation.alias_target(symbol.name()) == Some(target) {
      result.push(symbol.name())
    }
  }
  result.sort_by(lexical_compare)
  result
}

///|
fn list_text(
  loaded : @loader.LoadedSource,
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
) -> String {
  let docs = recipe_docs(loaded.ast())
  let rows : Array[(String, String, String?, String?)] = []
  let mut maximum = 0
  for name in visible_recipe_names(compilation, arguments) {
    guard compilation.recipe(name) is Some(recipe) else { continue }
    guard compilation.recipe_attributes(name) is Some(attributes) else {
      continue
    }
    let signature = recipe_signature(recipe)
    maximum = Int::max(maximum, display_width(signature))
    let doc = match attributes.doc() {
      Some(value) => Some(value)
      None => docs.get(name)
    }
    let aliases = if arguments.flag("no-aliases") {
      None
    } else {
      let values = alias_names(compilation, name)
      if values.is_empty() {
        None
      } else {
        Some(values.join(", "))
      }
    }
    rows.push((name, signature, doc, aliases))
  }
  let builder = StringBuilder()
  builder.write_string(
    arguments.value("list-heading").unwrap_or("Available recipes:\n"),
  )
  let prefix = arguments.value("list-prefix").unwrap_or("    ")
  for row in rows {
    let (name, signature, doc, aliases) = row
    guard compilation.recipe(name) is Some(recipe) else { continue }
    let group = match compilation.recipe_attributes(recipe.name()) {
      Some(value) => value.group()
      None => None
    }
    match group {
      Some(group) => {
        builder.write_string(prefix)
        builder.write_string("[")
        builder.write_string(group)
        builder.write_string("]\n")
      }
      None => ()
    }
    builder.write_string(prefix)
    builder.write_string(signature)
    let annotations : Array[String] = []
    match doc {
      Some(value) => annotations.push(value)
      None => ()
    }
    match aliases {
      Some(value) => annotations.push("[alias: " + value + "]")
      None => ()
    }
    if !annotations.is_empty() {
      let padding = Int::max(1, maximum - display_width(signature) + 1)
      for _ in 0..<padding {
        builder.write_char(' ')
      }
      builder.write_string("# ")
      builder.write_string(annotations.join(" "))
    }
    builder.write_char('\n')
  }
  builder.to_string()
}

///|
fn show_text(
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
) -> String raise ApplicationError {
  guard arguments.positional().get(0) is Some(requested) else {
    raise UnsupportedCommand("--show requires a recipe")
  }
  let name = compilation.alias_target(requested).unwrap_or(requested)
  guard compilation.recipe(name) is Some(recipe) else {
    raise UnsupportedCommand("unknown recipe " + requested)
  }
  @formatter.format(
    @syntax.Ast::new(compilation.source_id(), [Recipe(recipe)], recipe.span()),
  )
}

///|
fn usage_text(
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
) -> String raise ApplicationError {
  guard arguments.positional().get(0) is Some(requested) else {
    raise UnsupportedCommand("--usage requires a recipe")
  }
  let name = compilation.alias_target(requested).unwrap_or(requested)
  guard compilation.recipe(name) is Some(recipe) else {
    raise UnsupportedCommand("unknown recipe " + requested)
  }
  let builder = StringBuilder()
  builder.write_string("Usage: just ")
  builder.write_string(recipe.name())
  for parameter in recipe.parameters() {
    builder.write_char(' ')
    builder.write_string(parameter.name())
    if parameter.variadic() {
      builder.write_string("...")
    }
  }
  builder.write_string("\n")
  if !recipe.parameters().is_empty() {
    builder.write_string("\nArguments:\n")
    for parameter in recipe.parameters() {
      builder.write_string("  ")
      builder.write_string(parameter.name())
      if parameter.variadic() {
        builder.write_string("...")
      }
      builder.write_char('\n')
    }
  }
  builder.to_string()
}

///|
fn query_text(
  loaded : @loader.LoadedSource,
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
) -> String raise ApplicationError {
  match arguments.command() {
    ListCommand => list_text(loaded, compilation, arguments)
    ShowCommand => show_text(compilation, arguments)
    SummaryCommand =>
      visible_recipe_names(compilation, arguments).join(" ") + "\n"
    UsageCommand => usage_text(compilation, arguments)
    VariablesCommand => {
      let values = compilation.variable_names().to_owned()
      if !arguments.flag("unsorted") {
        values.sort_by(lexical_compare)
      }
      if values.is_empty() {
        ""
      } else {
        values.join("\n") + "\n"
      }
    }
    GroupsCommand => {
      let groups : Set[String] = Set([])
      for name in visible_recipe_names(compilation, arguments) {
        let group = match compilation.recipe_attributes(name) {
          Some(value) => value.group()
          None => None
        }
        match group {
          Some(group) => groups.add(group)
          None => ()
        }
      }
      let values = groups.to_array()
      values.sort_by(lexical_compare)
      if values.is_empty() {
        ""
      } else {
        "Recipe groups:\n" +
        values.map(fn(value) { "    " + value }).join("\n") +
        "\n"
      }
    }
    command => raise UnsupportedCommand("\{Repr(command)}")
  }
}

///|
pub fn[T : @host.HostFs] execute_query_command(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  let loaded = load_input(host, arguments, context)
  let compilation = compile_loaded(loaded)
  @cli.ApplicationResponse::success(
    stdout=@utf8.encode(query_text(loaded, compilation, arguments)),
  )
}
