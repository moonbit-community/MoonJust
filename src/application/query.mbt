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
    let suffix = match parameter.default_value() {
      Some(value) => "=" + @formatter.format_expression(value)
      None => ""
    }
    values.push(prefix + parameter.name() + suffix)
  }
  values.join(" ")
}

///|
fn lexical_compare(left : String, right : String) -> Int {
  let length = Int::min(left.length(), right.length())
  for index in 0..<length {
    let order = left.unsafe_get(index).compare(right.unsafe_get(index))
    if order != 0 {
      return order
    }
  }
  left.length().compare(right.length())
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
priv struct ListRow {
  name : String
  signature : String
  doc : String?
  aliases : Array[String]
  group : String?
}

///|
fn alias_annotation(aliases : ArrayView[String]) -> String {
  if aliases.length() == 1 {
    "[alias: " + aliases[0] + "]"
  } else {
    "[aliases: " + aliases.join(", ") + "]"
  }
}

///|
fn write_list_line(
  builder : StringBuilder,
  prefix : String,
  label : String,
  annotations : ArrayView[String],
  maximum : Int,
) -> Unit {
  builder.write_string(prefix)
  builder.write_string(label)
  if !annotations.is_empty() {
    let padding = Int::max(1, maximum - display_width(label) + 1)
    for _ in 0..<padding {
      builder.write_char(' ')
    }
    builder.write_string("# ")
    builder.write_string(annotations.join(" "))
  }
  builder.write_char('\n')
}

///|
fn alias_signature(row : ListRow, alias_name : String) -> String {
  alias_name + row.signature.view(start_offset=row.name.length()).to_owned()
}

///|
fn list_text(
  loaded : @loader.LoadedSource,
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
) -> String {
  let docs = recipe_docs(loaded.ast())
  let rows : Array[ListRow] = []
  let mut maximum = 0
  let alias_style = arguments.value("alias-style").unwrap_or("right")
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
      []
    } else {
      alias_names(compilation, name)
    }
    if alias_style == "separate" {
      for alias_name in aliases {
        maximum = Int::max(
          maximum,
          display_width(
            alias_name + signature.view(start_offset=name.length()).to_owned(),
          ),
        )
      }
    }
    rows.push({ name, signature, doc, aliases, group: attributes.group() })
  }
  let builder = StringBuilder()
  builder.write_string(
    arguments.value("list-heading").unwrap_or("Available recipes:\n"),
  )
  let prefix = arguments.value("list-prefix").unwrap_or("    ")
  let groups : Array[String] = []
  for row in rows {
    match row.group {
      Some(group) if !groups.contains(group) => groups.push(group)
      _ => ()
    }
  }
  if !arguments.flag("unsorted") {
    groups.sort_by(lexical_compare)
  }
  let sections : Array[String?] = [None]
  for group in groups {
    sections.push(Some(group))
  }
  let mut wrote_section = false
  for section in sections {
    let section_rows : Array[ListRow] = []
    for row in rows {
      if row.group == section {
        section_rows.push(row)
      }
    }
    if section_rows.is_empty() {
      continue
    }
    if wrote_section {
      builder.write_char('\n')
    }
    wrote_section = true
    match section {
      Some(group) => {
        builder.write_string(prefix)
        builder.write_string("[")
        builder.write_string(group)
        builder.write_string("]\n")
      }
      None => ()
    }
    for row in section_rows {
      let annotations : Array[String] = []
      if alias_style == "left" && !row.aliases.is_empty() {
        annotations.push(alias_annotation(row.aliases))
      }
      match row.doc {
        Some(value) => annotations.push(value)
        None => ()
      }
      if alias_style == "right" && !row.aliases.is_empty() {
        annotations.push(alias_annotation(row.aliases))
      }
      write_list_line(builder, prefix, row.signature, annotations, maximum)
      if alias_style == "separate" {
        for alias_name in row.aliases {
          write_list_line(
            builder,
            prefix,
            alias_signature(row, alias_name),
            ["alias for `" + row.name + "`"],
            maximum,
          )
        }
      }
    }
  }
  builder.to_string()
}

///|
fn show_text(
  loaded : @loader.LoadedSource,
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
        if recipe.attributes().is_empty() {
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
  if name != requested {
    builder.write_string("alias ")
    builder.write_string(requested)
    builder.write_string(" := ")
    builder.write_string(name)
    builder.write_char('\n')
  }
  builder.write_string("Usage: just ")
  builder.write_string(requested)
  for parameter in recipe.parameters() {
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
  if !recipe.parameters().is_empty() {
    builder.write_string("\nArguments:\n")
    for parameter in recipe.parameters() {
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
    ShowCommand => show_text(loaded, compilation, arguments)
    SummaryCommand =>
      visible_recipe_names(compilation, arguments).join(" ") + "\n"
    UsageCommand => usage_text(compilation, arguments)
    VariablesCommand => {
      let values = compilation.variable_names().to_owned()
      if values.is_empty() {
        ""
      } else {
        values.sort_by(lexical_compare)
        values.join(" ") + "\n"
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
      if !arguments.flag("unsorted") {
        values.sort_by(lexical_compare)
      }
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
