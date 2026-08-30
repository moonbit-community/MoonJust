///|
fn write_list_line(
  builder : StringBuilder,
  prefix : String,
  label : String,
  annotations : ArrayView[String],
  maximum : Int,
  color : Bool,
  rendered? : String = label,
) -> Unit {
  builder.write_string(prefix)
  builder.write_string(rendered)
  if !annotations.is_empty() {
    let padding = Int::max(1, maximum - @query.display_width(label) + 1)
    for _ in 0..<padding {
      builder.write_char(' ')
    }
    builder.write_string(paint("#", "34", color))
    builder.write_char(' ')
    builder.write_string(styled_doc(annotations.join(" "), color))
  }
  builder.write_char('\n')
}

///|
fn alias_signature(row : ListRow, alias_name : String) -> String {
  alias_name + row.signature.view(start_offset=row.name.length()).to_owned()
}

///|
fn rendered_alias_signature(row : ListRow, alias_name : String) -> String {
  alias_name +
  row.rendered_signature.view(start_offset=row.name.length()).to_owned()
}

///|
fn list_text(
  loaded : @loader.LoadedSource,
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
  color : Bool,
  hidden_recipes? : ArrayView[String] = [],
  hidden_aliases? : ArrayView[String] = [],
  project? : @semantic.ProjectCompilation,
  module_path? : @modulepath.ModulePath,
  globals? : Map[@modulepath.ModulePath, @evaluator.Environment],
  graph? : @loader.LoadedGraph,
) -> String raise ApplicationError {
  let docs = recipe_docs(loaded.ast())
  let list_environment = match (globals, module_path) {
    (Some(globals), Some(module_path)) =>
      globals.get(module_path).unwrap_or(@evaluator.Environment::new())
    _ =>
      @evaluator.evaluate_compilation(compilation) catch {
        error => raise Evaluation(error)
      }
  }
  if module_path.map(fn(path) { path.is_root() }).unwrap_or(true) {
    for group in arguments.values("group") {
      let mut found = false
      for name in compilation.recipe_names() {
        if hidden_recipes.contains(name) {
          continue
        }
        match compilation.recipe_attributes(name) {
          Some(attributes) if attributes.groups().contains(group) =>
            found = true
          _ => ()
        }
      }
      if !found {
        raise Query("justfile does not contain group `" + group + "`")
      }
    }
  }
  let rows : Array[ListRow] = []
  let mut maximum = 0
  let alias_style = arguments.value("alias-style").unwrap_or("right")
  for
    name in @query.visible_recipe_names(
      compilation,
      @query.build_query(arguments),
    ) {
    if hidden_recipes.contains(name) {
      continue
    }
    guard compilation.recipe(name) is Some(recipe) else { continue }
    guard compilation.recipe_attributes(name) is Some(attributes) else {
      continue
    }
    let signature = recipe_signature(recipe)
    let signature_width = @query.display_width(signature)
    if signature_width <= 50 {
      maximum = Int::max(maximum, signature_width)
    }
    let doc = if attributes.names().contains("doc") {
      match attributes.doc_expression() {
        Some(expression) => {
          let value = @evaluator.evaluate(
            expression,
            environment=list_environment,
          ) catch {
            error => raise Evaluation(error)
          }
          let text = value.to_string()
          if text.trim().is_empty() {
            None
          } else {
            Some(text)
          }
        }
        None => None
      }
    } else {
      docs.get(name)
    }
    let aliases = if arguments.flag("no-aliases") {
      []
    } else {
      alias_names(compilation, name, hidden=hidden_aliases)
    }
    if alias_style == "separate" {
      for alias_name in aliases {
        let alias_width = @query.display_width(
          alias_name + signature.view(start_offset=name.length()).to_owned(),
        )
        if alias_width <= 50 {
          maximum = Int::max(maximum, alias_width)
        }
      }
    }
    rows.push({
      name,
      signature,
      rendered_signature: styled_recipe_signature(recipe, color),
      doc,
      aliases,
      groups: attributes.groups().to_owned(),
      nested: None,
    })
  }
  if !arguments.flag("no-aliases") {
    for symbol in compilation.symbols() {
      if symbol.kind() is Alias &&
        !hidden_aliases.contains(symbol.name()) &&
        !symbol.name().has_prefix("_") &&
        !compilation.alias_private(symbol.name()) {
        guard compilation.alias_target(symbol.name()) is Some(target) else {
          continue
        }
        if target.contains("::") {
          maximum = Int::max(maximum, @query.display_width(symbol.name()))
          rows.push({
            name: symbol.name(),
            signature: symbol.name(),
            rendered_signature: symbol.name(),
            doc: Some("alias for `" + target + "`"),
            aliases: [],
            groups: [],
            nested: None,
          })
        }
      }
    }
  }
  match (project, module_path, globals, graph) {
    (Some(project), Some(module_path), Some(globals), Some(graph)) => {
      let children = direct_child_modules(
        project,
        module_path,
        arguments.flag("unsorted"),
      )
      for child in children {
        let name = child.components().last().unwrap()
        let child_compilation = project.module_compilation(child).unwrap()
        let child_hidden_recipes : Array[String] = []
        let child_hidden_aliases : Array[String] = []
        for recipe_name in child_compilation.recipe_names() {
          if project.recipe_disabled(child, recipe_name) {
            child_hidden_recipes.push(recipe_name)
          }
        }
        for symbol in child_compilation.symbols() {
          if symbol.kind() is Alias &&
            project.alias_disabled(child, symbol.name()) {
            child_hidden_aliases.push(symbol.name())
          }
        }
        let signature = if arguments.flag("list-submodules") {
          name + ":"
        } else {
          name + " ..."
        }
        maximum = Int::max(maximum, @query.display_width(signature))
        let doc = match
          evaluated_module_attribute(project, child, globals, "doc") {
          Some(value) if !value.trim().is_empty() => Some(value)
          Some(_) => None
          None if project
            .module_declaration_attributes(child)
            .any(fn(attribute) { attribute.name() == "doc" }) => None
          None => project.module_declaration_doc(child)
        }
        let module_groups : Array[String] = []
        for attribute in project.module_declaration_attributes(child) {
          if attribute.name() == "group" {
            match evaluated_module_attribute(project, child, globals, "group") {
              Some(group) if !module_groups.contains(group) =>
                module_groups.push(group)
              _ => ()
            }
          }
        }
        let nested = if arguments.flag("list-submodules") {
          let child_text = list_text(
            loaded_for_module(graph, child).unwrap(),
            child_compilation,
            arguments,
            color,
            hidden_recipes=child_hidden_recipes,
            hidden_aliases=child_hidden_aliases,
            project~,
            module_path=child,
            globals~,
            graph~,
          )
          Some(
            child_text
            .strip_prefix(
              arguments.value("list-heading").unwrap_or("Available recipes:\n"),
            )
            .unwrap_or("")
            .to_owned(),
          )
        } else {
          None
        }
        rows.push({
          name,
          signature,
          rendered_signature: signature,
          doc,
          aliases: [],
          groups: module_groups,
          nested,
        })
      }
    }
    _ => ()
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
    groups.sort_by(@query.lexical_compare)
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
    for index, row in section_rows {
      if section is None &&
        index > 0 &&
        section_rows[index - 1].nested is Some(_) {
        builder.write_char('\n')
      }
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
      if row.doc is Some(value) && value.contains("\n") {
        for line in value.split("\n") {
          if line.is_empty() {
            continue
          }
          builder.write_string(prefix)
          builder.write_string(paint("#", "34", color))
          builder.write_char(' ')
          builder.write_string(styled_doc(line.to_owned(), color))
          builder.write_char('\n')
        }
        let remaining : Array[String] = []
        if alias_style == "left" && !row.aliases.is_empty() {
          remaining.push(alias_annotation(row.aliases))
        }
        if alias_style == "right" && !row.aliases.is_empty() {
          remaining.push(alias_annotation(row.aliases))
        }
        write_list_line(
          builder,
          prefix,
          row.signature,
          remaining,
          maximum,
          color,
          rendered=row.rendered_signature,
        )
      } else if @query.display_width(row.signature) > 50 &&
        row.doc is Some(value) {
        builder.write_string(prefix)
        builder.write_string(paint("#", "34", color))
        builder.write_char(' ')
        builder.write_string(styled_doc(value, color))
        builder.write_char('\n')
        let remaining : Array[String] = []
        for annotation in annotations {
          if annotation != value {
            remaining.push(annotation)
          }
        }
        write_list_line(
          builder,
          prefix,
          row.signature,
          remaining,
          maximum,
          color,
          rendered=row.rendered_signature,
        )
      } else {
        write_list_line(
          builder,
          prefix,
          row.signature,
          annotations,
          maximum,
          color,
          rendered=row.rendered_signature,
        )
      }
      if alias_style == "separate" {
        for alias_name in row.aliases {
          write_list_line(
            builder,
            prefix,
            alias_signature(row, alias_name),
            ["alias for `" + row.name + "`"],
            maximum,
            color,
            rendered=rendered_alias_signature(row, alias_name),
          )
        }
      }
      match row.nested {
        Some(nested) => append_indented_text(builder, nested, prefix)
        None => ()
      }
    }
  }
  builder.to_string()
}

///|
