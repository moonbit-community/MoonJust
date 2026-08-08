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
priv struct ParameterDisplay {
  option : Bool
  flag : Bool
  help : String?
  long : String?
  pattern : Array[String]
  short : String?
  value : Bool
}

///|
fn parameter_display(
  recipe : @syntax.Recipe,
  parameter : @syntax.Parameter,
) -> ParameterDisplay {
  let mut flag = false
  let mut help : String? = None
  let mut long : String? = None
  let pattern : Array[String] = []
  let mut short : String? = None
  let mut value = false
  for attribute in recipe.attributes() {
    if attribute.name() != "arg" {
      continue
    }
    let arguments = attribute.arguments()
    guard arguments.get(0) is Some(first) else { continue }
    guard first.value() is Some(String(name)) else { continue }
    if name.cooked() != parameter.name() {
      continue
    }
    for argument in arguments[1:] {
      match argument.key() {
        Some("flag") => flag = true
        Some("help") =>
          match argument.value() {
            Some(String(text)) => help = Some(text.cooked())
            _ => ()
          }
        Some("long") =>
          match argument.value() {
            Some(String(text)) => long = Some(text.cooked())
            None => long = Some(parameter.name())
            _ => ()
          }
        Some("pattern") =>
          match argument.value() {
            Some(String(text)) => pattern.push(text.cooked())
            Some(List(elements~, ..)) =>
              for element in elements {
                if element is String(text) {
                  pattern.push(text.cooked())
                }
              }
            _ => ()
          }
        Some("short") =>
          match argument.value() {
            Some(String(text)) => short = Some(text.cooked())
            None =>
              short = parameter.name().to_array().get(0).map(Char::to_string)
            _ => ()
          }
        Some("value") => value = true
        _ => ()
      }
    }
  }
  {
    option: long is Some(_) || short is Some(_),
    flag,
    help,
    long,
    pattern,
    short,
    value,
  }
}

///|
fn recipe_signature(recipe : @syntax.Recipe) -> String {
  let values : Array[String] = [recipe.name()]
  let mut has_options = false
  for parameter in recipe.parameters() {
    if parameter_display(recipe, parameter).option {
      has_options = true
    }
  }
  if has_options {
    values.push("[OPTIONS]")
  }
  for parameter in recipe.parameters() {
    if parameter_display(recipe, parameter).option {
      continue
    }
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
fn edit_distance(left : String, right : String) -> Int {
  let a = left.to_array()
  let b = right.to_array()
  let previous : Array[Int] = Array::make(b.length() + 1, 0)
  let current : Array[Int] = Array::make(b.length() + 1, 0)
  for index in 0..<=b.length() {
    previous[index] = index
  }
  for row in 1..<=a.length() {
    current[0] = row
    for column in 1..<=b.length() {
      let substitution = previous[column - 1] +
        (if a[row - 1] == b[column - 1] { 0 } else { 1 })
      current[column] = Int::min(
        substitution,
        Int::min(previous[column] + 1, current[column - 1] + 1),
      )
    }
    for column in 0..<=b.length() {
      previous[column] = current[column]
    }
  }
  previous[b.length()]
}

///|
fn unknown_recipe_message(
  compilation : @semantic.Compilation,
  requested : String,
) -> String {
  let mut suggestion : String? = None
  let mut suggestion_target : String? = None
  let mut best = 3
  let names : Array[String] = []
  for symbol in compilation.symbols() {
    if symbol.kind() is Recipe || symbol.kind() is Alias {
      names.push(symbol.name())
    }
  }
  names.sort_by(lexical_compare)
  for name in names {
    let distance = edit_distance(requested, name)
    if distance < best {
      best = distance
      suggestion = Some(name)
      suggestion_target = compilation.alias_target(name)
    }
  }
  let base = "justfile does not contain recipe `" + requested + "`"
  match suggestion {
    Some(name) => {
      let suffix = match suggestion_target {
        Some(target) => ", an alias for `" + target + "`?"
        None => "?"
      }
      base + "\nDid you mean `" + name + "`" + suffix
    }
    None => base
  }
}

///|
fn visible_recipe_names(
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
) -> Array[String] {
  let result : Array[String] = []
  let requested_groups = arguments.values("group")
  for name in compilation.recipe_names() {
    match compilation.recipe_attributes(name) {
      Some(attributes) if !attributes.private() &&
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
  groups : Array[String]
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
) -> String raise ApplicationError {
  let docs = recipe_docs(loaded.ast())
  for group in arguments.values("group") {
    let mut found = false
    for name in compilation.recipe_names() {
      match compilation.recipe_attributes(name) {
        Some(attributes) if attributes.groups().contains(group) => found = true
        _ => ()
      }
    }
    if !found {
      raise Query("justfile does not contain group `" + group + "`")
    }
  }
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
      Some(value) if !value.trim().is_empty() => Some(value)
      Some(_) => None
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
    rows.push({
      name,
      signature,
      doc,
      aliases,
      groups: attributes.groups().to_owned(),
    })
  }
  let builder = StringBuilder()
  builder.write_string(
    arguments.value("list-heading").unwrap_or("Available recipes:\n"),
  )
  let prefix = arguments.value("list-prefix").unwrap_or("    ")
  let groups : Array[String] = []
  for row in rows {
    for group in row.groups {
      if !groups.contains(group) {
        groups.push(group)
      }
    }
  }
  if !arguments.flag("unsorted") {
    groups.sort_by(lexical_compare)
  }
  let sections : Array[String?] = []
  if arguments.values("group").is_empty() {
    sections.push(None)
    for group in groups {
      sections.push(Some(group))
    }
  } else {
    for group in arguments.values("group") {
      sections.push(Some(group))
    }
  }
  let mut wrote_section = false
  for section in sections {
    let section_rows : Array[ListRow] = []
    for row in rows {
      match section {
        None if row.groups.is_empty() => section_rows.push(row)
        Some(group) if row.groups.contains(group) => section_rows.push(row)
        _ => ()
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
  builder.write_string(requested)
  let mut has_options = false
  let mut has_arguments = false
  for parameter in recipe.parameters() {
    let display = parameter_display(recipe, parameter)
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
    if parameter_display(recipe, parameter).option {
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
      let display = parameter_display(recipe, parameter)
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
      let display = parameter_display(recipe, parameter)
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
      if !arguments.positional().is_empty() {
        raise Query(
          "`--groups` used with unexpected argument: `" +
          arguments.positional()[0] +
          "`",
        )
      }
      let groups : Array[String] = []
      for name in visible_recipe_names(compilation, arguments) {
        match compilation.recipe_attributes(name) {
          Some(value) =>
            for group in value.groups() {
              if !groups.contains(group) {
                groups.push(group)
              }
            }
          None => ()
        }
      }
      let values = groups
      if !arguments.flag("unsorted") {
        values.sort_by(lexical_compare)
      }
      if values.is_empty() {
        ""
      } else {
        "Recipe groups:\n" +
        values
        .map(fn(value) {
          arguments.value("list-prefix").unwrap_or("    ") + value
        })
        .join("\n") +
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
  let output = query_text(loaded, compilation, arguments)
  let stderr = if arguments.command() == SummaryCommand &&
    visible_recipe_names(compilation, arguments).is_empty() {
    b"justfile contains no recipes\n"
  } else {
    b""
  }
  @cli.ApplicationResponse::success(stdout=@utf8.encode(output), stderr~)
}
