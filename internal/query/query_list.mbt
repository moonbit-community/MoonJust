///|
fn write_list_line(
  builder : StringBuilder,
  prefix : String,
  label : String,
  annotations : ArrayView[String],
  maximum : Int32,
  color : Bool,
  rendered~ : String = label,
) -> Unit {
  builder.write_string(prefix)
  builder.write_string(rendered)
  if !annotations.is_empty() {
    let padding = Int32::max(1, maximum - display_width(label) + 1)
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
  alias_name + row.signature[row.name.length():].to_owned()
}

///|
fn rendered_alias_signature(row : ListRow, alias_name : String) -> String {
  alias_name + row.rendered_signature[row.name.length():].to_owned()
}

///|
fn list_body(
  graph : @loader.LoadedGraph,
  project : @semantic.ProjectCompilation,
  module_path : @modulepath.ModulePath,
  options : ListOptions,
  color : Bool,
  globals : Map[@modulepath.ModulePath, @evaluator.Environment],
) -> String raise QueryError {
  let compilation = project.module_compilation(module_path).unwrap()
  guard loaded_for_module(graph, module_path) is Some(loaded) else {
    raise Query(
      "source for module `" + module_path.as_string() + "` is unavailable",
    )
  }
  let docs = recipe_docs(loaded.ast())
  let list_environment = globals
    .get(module_path)
    .unwrap_or(@evaluator.Environment::new())
  let hidden_aliases : Array[String] = []
  for symbol in compilation.symbols() {
    if symbol.kind() is Alias &&
      project.alias_disabled(module_path, symbol.name()) {
      hidden_aliases.push(symbol.name())
    }
  }
  if module_path.is_root() {
    for group in options.filter.groups {
      let mut found = false
      for name in compilation.recipe_names() {
        if project.recipe_disabled(module_path, name) {
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
  let alias_style = options.alias_style
  for name in visible_recipe_names(compilation, options.filter) {
    if project.recipe_disabled(module_path, name) {
      continue
    }
    guard compilation.recipe(name) is Some(recipe) else { continue }
    guard compilation.recipe_attributes(name) is Some(attributes) else {
      continue
    }
    let signature = recipe_signature(recipe)
    let signature_width = display_width(signature)
    if signature_width <= 50 {
      maximum = Int32::max(maximum, signature_width)
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
    let aliases = if options.hide_aliases {
      []
    } else {
      alias_names(compilation, name, hidden=hidden_aliases)
    }
    if alias_style == "separate" {
      for alias_name in aliases {
        let alias_width = display_width(
          alias_name + signature[name.length():].to_owned(),
        )
        if alias_width <= 50 {
          maximum = Int32::max(maximum, alias_width)
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
  if !options.hide_aliases {
    for symbol in compilation.symbols() {
      if symbol.kind() is Alias &&
        !hidden_aliases.contains(symbol.name()) &&
        !symbol.name().has_prefix("_") &&
        !compilation.alias_private(symbol.name()) {
        guard compilation.alias_target(symbol.name()) is Some(target) else {
          continue
        }
        if target.contains("::") {
          maximum = Int32::max(maximum, display_width(symbol.name()))
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
  let children = direct_child_modules(
    project,
    module_path,
    options.filter.unsorted,
  )
  for child in children {
    let name = child.components().last().unwrap()
    let signature = if options.submodules { name + ":" } else { name + " ..." }
    maximum = Int32::max(maximum, display_width(signature))
    let doc = match evaluated_module_attribute(project, child, globals, "doc") {
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
    let nested = if options.submodules {
      Some(list_body(graph, project, child, options, color, globals))
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
  let builder = StringBuilder()
  let prefix = options.prefix
  let groups : Array[String] = []
  for row in rows {
    for group in row.groups {
      if !groups.contains(group) {
        groups.push(group)
      }
    }
  }
  if !options.filter.unsorted {
    groups.sort_by(lexical_compare)
  }
  let sections : Array[String?] = []
  if options.filter.groups.is_empty() {
    sections.push(None)
    for group in groups {
      sections.push(Some(group))
    }
  } else {
    for group in options.filter.groups {
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
      } else if display_width(row.signature) > 50 && row.doc is Some(value) {
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
