///|
fn append_project_source_items(
  files : ArrayView[@loader.LoadedSource],
  index : Int,
  visited : Array[Int],
  items : Array[@syntax.Item],
) -> Unit {
  if visited.contains(index) {
    return
  }
  visited.push(index)
  let loaded = files[index]
  for item in loaded.ast().items() {
    match item {
      Import(_) | Module(_) => ()
      _ => items.push(item)
    }
  }
  for item in loaded.ast().items() {
    match item {
      Import(value) => {
        let mut child : Int? = None
        for candidate_index, candidate in files {
          if candidate.relation() == ImportedSource &&
            candidate.parent() == Some(loaded.path()) &&
            candidate.import_span() == Some(value.span()) &&
            candidate.module_path() == loaded.module_path() {
            child = Some(candidate_index)
            break
          }
        }
        match child {
          Some(child_index) =>
            append_project_source_items(files, child_index, visited, items)
          None => ()
        }
      }
      _ => ()
    }
  }
}

///|
fn source_import_depth(
  files : ArrayView[@loader.LoadedSource],
  owner : @loader.LoadedSource,
  source_id : @source.SourceId,
) -> Int {
  let mut current : @loader.LoadedSource? = None
  for loaded in files {
    if loaded.ast().source_id() == source_id &&
      loaded.module_path() == owner.module_path() {
      current = Some(loaded)
      break
    }
  }
  let mut depth = 0
  while current is Some(loaded) && loaded.path() != owner.path() {
    guard loaded.parent() is Some(parent) else { break }
    let mut next : @loader.LoadedSource? = None
    for candidate in files {
      if candidate.path() == parent &&
        candidate.module_path() == owner.module_path() {
        next = Some(candidate)
        break
      }
    }
    current = next
    depth += 1
  }
  depth
}

///|
fn import_override_key(item : @syntax.Item) -> String? {
  match item {
    Recipe(recipe) => Some("recipe\u{0000}" + recipe.name())
    Assignment(assignment) => Some("variable\u{0000}" + assignment.name())
    Alias(definition) => Some("alias\u{0000}" + definition.name())
    _ => None
  }
}

///|
fn apply_import_overrides(
  files : ArrayView[@loader.LoadedSource],
  owner : @loader.LoadedSource,
  items : ArrayView[@syntax.Item],
) -> Array[@syntax.Item] {
  // A source-local compilation cannot have import shadowing. Avoid the
  // quadratic override scan for the overwhelmingly common single-source
  // graph while retaining the full path for imported definitions.
  if items.length() > 1 {
    let source_id = items[0].span().source_id()
    if items.all(fn(item) { item.span().source_id() == source_id }) {
      return items.to_owned()
    }
  }
  let result : Array[@syntax.Item] = []
  let included : Array[Bool] = []
  for item in items {
    let mut include_current = true
    guard import_override_key(item) is Some(key) else {
      result.push(item)
      included.push(true)
      continue
    }
    let current_source = item.span().source_id()
    let current_depth = source_import_depth(files, owner, current_source)
    for previous, previous_item in result {
      if !included[previous] ||
        import_override_key(previous_item) != Some(key) ||
        previous_item.span().source_id() == current_source {
        continue
      }
      let previous_depth = source_import_depth(
        files,
        owner,
        previous_item.span().source_id(),
      )
      if current_depth < previous_depth {
        included[previous] = false
      } else if current_depth > previous_depth {
        include_current = false
        break
      }
    }
    result.push(item)
    included.push(include_current)
  }
  let merged : Array[@syntax.Item] = []
  for index, item in result {
    if included[index] {
      merged.push(item)
    }
  }
  merged
}

///|
fn module_declaration_metadata(
  files : ArrayView[@loader.LoadedSource],
  loaded : @loader.LoadedSource,
) -> (Array[@syntax.Attribute], String?, @source.Span?) {
  guard loaded.relation() == ModuleSource else { return ([], None, None) }
  guard loaded.parent() is Some(parent_path) else { return ([], None, None) }
  guard loaded.import_span() is Some(declaration_span) else {
    return ([], None, None)
  }
  for parent in files {
    if parent.path() != parent_path {
      continue
    }
    let pending_docs : Array[String] = []
    for item in parent.ast().items() {
      match item {
        Comment(text~, ..) => {
          let trimmed = text.trim()
          if trimmed.has_prefix("# ") {
            pending_docs.push(trimmed.view(start_offset=2).to_owned())
          } else {
            pending_docs.clear()
          }
        }
        Module(definition) if definition.span() == declaration_span =>
          return (
            definition.attributes().to_owned(),
            if pending_docs.is_empty() {
              None
            } else {
              Some(pending_docs.join(" "))
            },
            Some(definition.name_span()),
          )
        Blank(_) => pending_docs.clear()
        _ => pending_docs.clear()
      }
    }
  }
  ([], None, None)
}

///|
fn validate_module_name_conflicts(
  files : ArrayView[@loader.LoadedSource],
  platform : @semantic.TargetPlatform,
) -> Unit raise ApplicationError {
  let definitions : Map[String, (String, @source.Span)] = Map([])
  for loaded in files {
    let prefix = loaded.module_path().as_string() + "\u{0000}"
    for item in loaded.ast().items() {
      let entry : (String, String)? = match item {
        Module(definition) if @semantic.platform_attributes_match(
            definition.attributes(),
            platform,
          ) => {
          let mut present = false
          for candidate in files {
            if candidate.relation() == ModuleSource &&
              candidate.parent() == Some(loaded.path()) &&
              candidate.import_span() == Some(definition.span()) {
              present = true
              break
            }
          }
          if present || !definition.optional() {
            Some((definition.name(), "module"))
          } else {
            None
          }
        }
        Recipe(recipe) if @semantic.platform_attributes_match(
            recipe.attributes(),
            platform,
          ) => Some((recipe.name(), "recipe"))
        Alias(definition) if @semantic.platform_attributes_match(
            definition.attributes(),
            platform,
          ) => Some((definition.name(), "alias"))
        _ => None
      }
      guard entry is Some((name, kind)) else { continue }
      let key = prefix + name
      let offset = if kind == "module" {
        4
      } else if kind == "alias" {
        6
      } else {
        0
      }
      let span = @source.Span::new(
        item.span().source_id(),
        item.span().start_byte() + offset,
        item.span().start_byte() + offset + name.length(),
      ) catch {
        _ => item.span()
      }
      match definitions.get(key) {
        Some((previous, first)) if previous != kind || kind == "module" =>
          raise Semantic(
            SymbolRedefinition(
              name~,
              first_kind=previous,
              second_kind=kind,
              first~,
              second=span,
            ),
          )
        Some(_) => ()
        None => definitions[key] = (kind, span)
      }
    }
  }
}

///|
fn compile_loaded_graph(
  graph : @loader.LoadedGraph,
  allow_unstable? : Bool = false,
  platform? : @semantic.TargetPlatform = @semantic.TargetPlatform::new(
    Other("unknown"),
    false,
  ),
) -> @semantic.ProjectCompilation raise ApplicationError {
  let entries : Array[@semantic.ProjectModule] = []
  let absent_modules : Array[@modulepath.ModulePath] = []
  let files = graph.files()
  validate_module_name_conflicts(files, platform)
  for index, loaded in files {
    if loaded.relation() != RootSource && loaded.relation() != ModuleSource {
      continue
    }
    let items : Array[@syntax.Item] = []
    append_project_source_items(files, index, [], items)
    let items = apply_import_overrides(files, loaded, items)
    let ast = @syntax.Ast::new(
      loaded.ast().source_id(),
      items,
      loaded.ast().span(),
    )
    let compilation = @semantic.compile(
      ast,
      platform~,
      allow_unstable~,
      defer_recipe_linking=true,
    ) catch {
      error => raise Semantic(error)
    }
    let (declaration_attributes, declaration_doc, declaration_name_span) = module_declaration_metadata(
      files, loaded,
    )
    let source_files : Array[(@source.SourceId, @path.PathValue)] = []
    for source in files {
      if source.module_path() == loaded.module_path() {
        source_files.push((source.ast().source_id(), source.path()))
      }
    }
    let mut default_recipe : String? = None
    for item in loaded.ast().items() {
      guard item is Recipe(recipe) &&
        compilation.recipe(recipe.name()) is Some(_) else {
        continue
      }
      if default_recipe is None {
        default_recipe = Some(recipe.name())
      }
      if recipe
        .attributes()
        .any(fn(attribute) { attribute.name() == "default" }) {
        default_recipe = Some(recipe.name())
        break
      }
    }
    for attribute in declaration_attributes {
      if ![
          "doc", "group", "private", "aix", "android", "dragonfly", "freebsd", "haiku",
          "illumos", "ios", "linux", "macos", "netbsd", "openbsd", "solaris", "unix",
          "windows",
        ].contains(attribute.name()) {
        raise Semantic(
          InvalidItemAttribute(
            item_kind="module",
            item_name=loaded.module_path().as_string(),
            attribute=attribute.name(),
            span=declaration_name_span.unwrap_or(
              loaded.import_span().unwrap_or(attribute.span()),
            ),
          ),
        )
      }
    }
    entries.push(
      @semantic.ProjectModule::new(
        loaded.module_path(),
        compilation,
        loaded.module_directory(),
        source_file=loaded.path(),
        source_files~,
        declaration_attributes~,
        declaration_doc?,
        default_recipe?,
      ),
    )
  }
  for loaded in files {
    for item in loaded.ast().items() {
      guard item is Module(definition) &&
        definition.optional() &&
        @semantic.platform_attributes_match(definition.attributes(), platform) else {
        continue
      }
      let child_path = try! loaded.module_path().child(definition.name())
      let mut present = false
      for candidate in files {
        if candidate.relation() == ModuleSource &&
          candidate.module_path() == child_path {
          present = true
          break
        }
      }
      if !present && !absent_modules.contains(child_path) {
        absent_modules.push(child_path)
      }
    }
  }
  let project = @semantic.ProjectCompilation::new(entries, absent_modules~) catch {
    error => raise Project(error)
  }
  @semantic.validate_project_compilation(project) catch {
    error => raise Semantic(error)
  }
  project
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
  environment? : @evaluator.Environment,
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
          match (argument.value(), environment) {
            (Some(expression), Some(environment)) => {
              let value = @evaluator.evaluate(expression, environment~) catch {
                _ => List([])
              }
              let elements = value.elements()
              if !elements.is_empty() {
                help = Some(elements.join(" "))
              }
            }
            (Some(String(text)), None) => help = Some(text.cooked())
            _ => ()
          }
        Some("long") =>
          match argument.value() {
            Some(String(text)) => long = Some(text.cooked())
            None => long = Some(parameter.name())
            _ => ()
          }
        Some("pattern") =>
          match (argument.value(), environment) {
            (Some(expression), Some(environment)) => {
              let value = @evaluator.evaluate(expression, environment~) catch {
                _ => List([])
              }
              pattern.append(value.elements())
            }
            (Some(String(text)), None) => pattern.push(text.cooked())
            (Some(List(elements~, ..)), None) =>
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
fn styled_recipe_signature(recipe : @syntax.Recipe, color : Bool) -> String {
  if !color {
    return recipe_signature(recipe)
  }
  let values : Array[String] = [recipe.name()]
  let mut has_options = false
  for parameter in recipe.parameters() {
    if parameter_display(recipe, parameter).option {
      has_options = true
    }
  }
  if has_options {
    values.push(paint("[OPTIONS]", "36", true))
  }
  for parameter in recipe.parameters() {
    if parameter_display(recipe, parameter).option {
      continue
    }
    let prefix = if parameter.variadic() {
      paint(
        if parameter.variadic_minimum() == 0 {
          "*"
        } else {
          "+"
        },
        "35",
        true,
      )
    } else {
      ""
    }
    let suffix = match parameter.default_value() {
      Some(value) =>
        "=" + paint(@formatter.format_expression(value), "32", true)
      None => ""
    }
    values.push(prefix + paint(parameter.name(), "36", true) + suffix)
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
fn closest_name(requested : String, names : Array[String]) -> String? {
  names.sort_by(lexical_compare)
  let mut suggestion : String? = None
  let mut best = 3
  for name in names {
    let distance = edit_distance(requested, name)
    if distance < best {
      best = distance
      suggestion = Some(name)
    }
  }
  suggestion
}

///|
fn direct_submodule_names(
  project : @semantic.ProjectCompilation,
  parent : @modulepath.ModulePath,
) -> Array[String] {
  let names : Array[String] = []
  for path in project.module_paths() {
    if path.parent() == Some(parent) && path.components().last() is Some(name) {
      names.push(name)
    }
  }
  names
}

///|
fn unknown_submodule_message(
  project : @semantic.ProjectCompilation,
  parent : @modulepath.ModulePath,
  requested : String,
  display? : String,
) -> String {
  let base = "justfile does not contain submodule `" +
    display.unwrap_or(requested) +
    "`"
  match closest_name(requested, direct_submodule_names(project, parent)) {
    Some(name) => base + "\nDid you mean `" + name + "`?"
    None => base
  }
}

///|
fn unknown_recipe_message(
  compilation : @semantic.Compilation,
  requested : String,
) -> String {
  let mut suggestion_target : String? = None
  let names : Array[String] = []
  for symbol in compilation.symbols() {
    if symbol.kind() is Recipe || symbol.kind() is Alias {
      names.push(symbol.name())
    }
  }
  let suggestion = closest_name(requested, names)
  if suggestion is Some(name) {
    suggestion_target = compilation.alias_target(name)
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
fn alias_names(
  compilation : @semantic.Compilation,
  target : String,
  hidden? : ArrayView[String] = [],
) -> Array[String] {
  let result : Array[String] = []
  for symbol in compilation.symbols() {
    if symbol.kind() is Alias &&
      !hidden.contains(symbol.name()) &&
      !symbol.name().has_prefix("_") &&
      !compilation.alias_private(symbol.name()) &&
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
  rendered_signature : String
  doc : String?
  aliases : Array[String]
  groups : Array[String]
  nested : String?
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
fn paint(value : String, code : String, active : Bool) -> String {
  if active {
    "\u{001b}[" + code + "m" + value + "\u{001b}[0m"
  } else {
    value
  }
}

///|
fn styled_doc(value : String, active : Bool) -> String {
  if !active {
    return value
  }
  let characters = value.to_array()
  let builder = StringBuilder()
  let mut start = 0
  let mut index = 0
  while index < characters.length() {
    if characters[index] != '`' {
      index += 1
      continue
    }
    if start < index {
      builder.write_string(
        paint(String::from_array(characters[start:index]), "34", true),
      )
    }
    let mut end = index + 1
    while end < characters.length() && characters[end] != '`' {
      end += 1
    }
    if end < characters.length() {
      end += 1
    }
    builder.write_string(
      paint(String::from_array(characters[index:end]), "36", true),
    )
    start = end
    index = end
  }
  if start < characters.length() {
    builder.write_string(
      paint(String::from_array(characters[start:]), "34", true),
    )
  }
  builder.to_string()
}

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
    let padding = Int::max(1, maximum - display_width(label) + 1)
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
  for name in visible_recipe_names(compilation, arguments) {
    if hidden_recipes.contains(name) {
      continue
    }
    guard compilation.recipe(name) is Some(recipe) else { continue }
    guard compilation.recipe_attributes(name) is Some(attributes) else {
      continue
    }
    let signature = recipe_signature(recipe)
    let signature_width = display_width(signature)
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
        let alias_width = display_width(
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
          maximum = Int::max(maximum, display_width(symbol.name()))
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
        maximum = Int::max(maximum, display_width(signature))
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

///|
fn loaded_for_module(
  graph : @loader.LoadedGraph,
  path : @modulepath.ModulePath,
) -> @loader.LoadedSource? {
  for loaded in graph.files() {
    if loaded.module_path() == path &&
      (loaded.relation() == RootSource || loaded.relation() == ModuleSource) {
      return Some(loaded)
    }
  }
  None
}

///|
fn module_path_from_arguments(
  project : @semantic.ProjectCompilation,
  arguments : ArrayView[String],
) -> @modulepath.ModulePath raise ApplicationError {
  if arguments.is_empty() {
    return @modulepath.ModulePath::root()
  }
  let requested = if arguments.length() == 1 {
    arguments[0]
  } else {
    arguments.join("::")
  }
  match project.resolve_module(@modulepath.ModulePath::root(), requested) {
    Some(path) => path
    None =>
      match
        project.absent_module_for_reference(
          @modulepath.ModulePath::root(),
          requested,
        ) {
        Some(absent) =>
          raise Query("optional module `" + absent.as_string() + "` is absent")
        None =>
          raise Query(
            unknown_submodule_message(
              project,
              @modulepath.ModulePath::root(),
              requested,
            ),
          )
      }
  }
}

///|
fn query_recipe_path(
  project : @semantic.ProjectCompilation,
  arguments : ArrayView[String],
) -> (@modulepath.ModulePath, String, String) raise ApplicationError {
  if arguments.is_empty() {
    raise Query("recipe path is required")
  }
  if arguments.length() > 1 &&
    project.resolve_module(@modulepath.ModulePath::root(), arguments[0]) is None {
    raise Query("unexpected argument: `" + arguments[1] + "`")
  }
  let (requested, display) = if arguments.length() == 1 {
    (
      arguments[0].split(" ").filter(fn(part) { !part.is_empty() }).join("::"),
      arguments[0],
    )
  } else {
    (arguments.join("::"), arguments.join(" "))
  }
  let parsed = try @modulepath.ModulePath::parse(requested) catch {
    _ => raise Query("invalid recipe path `" + display + "`")
  } noraise {
    value => value
  }
  if project.absent_module_for_reference(
      @modulepath.ModulePath::root(),
      requested,
    )
    is Some(absent) {
    raise Query("optional module `" + absent.as_string() + "` is absent")
  }
  let components = parsed.components()
  if components.last() is Some(local_name) {
    let prefix = components[:components.length() - 1].join("::")
    let module_path = if prefix.is_empty() {
      Some(@modulepath.ModulePath::root())
    } else {
      project.resolve_module(@modulepath.ModulePath::root(), prefix)
    }
    match module_path {
      Some(path) => {
        let compilation = project.module_compilation(path).unwrap()
        if compilation.alias_target(local_name) is Some(_) &&
          project.resolve_recipe(path, local_name) is Some(_) {
          return (path, local_name, display)
        }
      }
      None => ()
    }
  }
  match project.resolve_recipe(@modulepath.ModulePath::root(), requested) {
    Some(recipe) => (recipe.module_path(), recipe.recipe_name(), display)
    None => {
      guard components.last() is Some(local_name) else {
        raise Query("unknown recipe `" + display + "`")
      }
      if components.length() == 1 {
        return (@modulepath.ModulePath::root(), local_name, display)
      }
      let prefix = components[:components.length() - 1].join("::")
      match project.resolve_module(@modulepath.ModulePath::root(), prefix) {
        Some(path) => (path, local_name, display)
        None => {
          let requested_component = components[0]
          raise Query(
            unknown_submodule_message(
              project,
              @modulepath.ModulePath::root(),
              requested_component,
              display=prefix,
            ),
          )
        }
      }
    }
  }
}

///|
fn direct_child_modules(
  project : @semantic.ProjectCompilation,
  parent : @modulepath.ModulePath,
  unsorted : Bool,
) -> Array[@modulepath.ModulePath] {
  let result : Array[@modulepath.ModulePath] = []
  for path in project.module_paths() {
    if path.parent() == Some(parent) &&
      !project
      .module_declaration_attributes(path)
      .any(fn(attribute) { attribute.name() == "private" }) {
      result.push(path)
    }
  }
  if !unsorted {
    result.sort_by(fn(left, right) {
      lexical_compare(left.as_string(), right.as_string())
    })
  }
  result
}

///|
fn evaluated_module_attribute(
  project : @semantic.ProjectCompilation,
  path : @modulepath.ModulePath,
  globals : Map[@modulepath.ModulePath, @evaluator.Environment],
  name : String,
) -> String? raise ApplicationError {
  let environment_path = path.parent().unwrap_or(@modulepath.ModulePath::root())
  let environment = globals
    .get(environment_path)
    .unwrap_or(@evaluator.Environment::new())
  for attribute in project.module_declaration_attributes(path) {
    if attribute.name() != name || attribute.arguments().is_empty() {
      continue
    }
    guard attribute.arguments()[0].value() is Some(expression) else { continue }
    let value = @evaluator.evaluate(expression, environment~) catch {
      error => raise Evaluation(error)
    }
    return Some(value.to_string())
  }
  None
}

///|
fn append_indented_text(
  builder : StringBuilder,
  text : String,
  indentation : String,
) -> Unit {
  let mut line_start = true
  for character in text {
    if line_start && character != '\n' {
      builder.write_string(indentation)
    }
    builder.write_char(character)
    line_start = character == '\n'
  }
}

///|
fn append_project_list_module(
  builder : StringBuilder,
  graph : @loader.LoadedGraph,
  project : @semantic.ProjectCompilation,
  path : @modulepath.ModulePath,
  arguments : @cli.CliArguments,
  color : Bool,
  depth : Int,
  globals : Map[@modulepath.ModulePath, @evaluator.Environment],
) -> Unit raise ApplicationError {
  let compilation = project.module_compilation(path).unwrap()
  guard loaded_for_module(graph, path) is Some(loaded) else {
    raise Query("source for module `" + path.as_string() + "` is unavailable")
  }
  let heading = arguments
    .value("list-heading")
    .unwrap_or("Available recipes:\n")
  let hidden_recipes : Array[String] = []
  let hidden_aliases : Array[String] = []
  for name in compilation.recipe_names() {
    if project.recipe_disabled(path, name) {
      hidden_recipes.push(name)
    }
  }
  for symbol in compilation.symbols() {
    if symbol.kind() is Alias && project.alias_disabled(path, symbol.name()) {
      hidden_aliases.push(symbol.name())
    }
  }
  let body = list_text(
      loaded,
      compilation,
      arguments,
      color,
      hidden_recipes~,
      hidden_aliases~,
      project~,
      module_path=path,
      globals~,
      graph~,
    )
    .strip_prefix(heading)
    .unwrap_or("")
    .to_owned()
  let prefix = arguments.value("list-prefix").unwrap_or("    ")
  append_indented_text(builder, body, prefix.repeat(depth))
  if !body.is_empty() && !body.has_suffix("\n") {
    builder.write_char('\n')
  }
}

///|
fn project_summary_text(
  project : @semantic.ProjectCompilation,
  arguments : @cli.CliArguments,
) -> String {
  let names : Array[String] = []
  for path in project.module_paths() {
    let compilation = project.module_compilation(path).unwrap()
    for name in visible_recipe_names(compilation, arguments) {
      if project.recipe_disabled(path, name) {
        continue
      }
      names.push(
        if path.is_root() {
          name
        } else {
          path.as_string() + "::" + name
        },
      )
    }
  }
  names.join(" ") + "\n"
}

///|
fn query_project_text(
  graph : @loader.LoadedGraph,
  project : @semantic.ProjectCompilation,
  arguments : @cli.CliArguments,
  color : Bool,
) -> String raise ApplicationError {
  match arguments.command() {
    SummaryCommand => project_summary_text(project, arguments)
    ListCommand => {
      let globals = evaluate_project_globals(project, arguments)
      let path = module_path_from_arguments(project, arguments.positional())
      if project.module_compilation(path) is None {
        raise Query("unknown module `" + path.as_string() + "`")
      }
      let builder = StringBuilder()
      builder.write_string(
        arguments.value("list-heading").unwrap_or("Available recipes:\n"),
      )
      append_project_list_module(
        builder, graph, project, path, arguments, color, 0, globals,
      )
      builder.to_string()
    }
    ShowCommand => {
      if arguments.positional().is_empty() {
        raise Query("`--show` requires recipe")
      }
      let (path, recipe, _) = query_recipe_path(project, arguments.positional())
      let compilation = project.module_compilation(path).unwrap()
      if project.alias_disabled(path, recipe) {
        let modules = project.alias_absent_modules(path, recipe)
        raise Query(
          "alias `" +
          recipe +
          "` depends on absent module" +
          (if modules.length() == 1 { " `" } else { "s `" }) +
          modules.map(fn(value) { value.as_string() }).join("` and `") +
          "`",
        )
      }
      if project.recipe_disabled(path, recipe) {
        let modules = project.recipe_absent_modules(path, recipe)
        raise Query(
          "recipe `" +
          recipe +
          "` depends on absent module" +
          (if modules.length() == 1 { " `" } else { "s `" }) +
          modules.map(fn(value) { value.as_string() }).join("` and `") +
          "`",
        )
      }
      match compilation.alias_target(recipe) {
        Some(target) =>
          match project.resolve_recipe(path, recipe) {
            Some(resolved) if resolved.module_path() != path =>
              "alias " +
              recipe +
              " := " +
              target +
              "\n" +
              show_recipe_text(
                loaded_for_module(graph, resolved.module_path()).unwrap(),
                project.module_compilation(resolved.module_path()).unwrap(),
                resolved.recipe_name(),
              )
            _ =>
              show_recipe_text(
                loaded_for_module(graph, path).unwrap(),
                compilation,
                recipe,
              )
          }
        None =>
          show_recipe_text(
            loaded_for_module(graph, path).unwrap(),
            compilation,
            recipe,
          )
      }
    }
    UsageCommand => {
      if arguments.positional().is_empty() {
        raise Query("`--usage` requires recipe")
      }
      let (path, recipe, display) = query_recipe_path(
        project,
        arguments.positional(),
      )
      let globals = evaluate_project_globals(project, arguments)
      usage_recipe_text(
        project.module_compilation(path).unwrap(),
        recipe,
        display,
        environment=globals[path],
      )
    }
    _ => {
      let loaded = graph.files()[0]
      query_text(loaded, project.root(), arguments, color)
    }
  }
}

///|
fn default_list_module_path(
  project : @semantic.ProjectCompilation,
  arguments : ArrayView[String],
) -> @modulepath.ModulePath? {
  if arguments.is_empty() {
    return Some(@modulepath.ModulePath::root())
  }
  let requested = if arguments.length() == 1 {
    arguments[0]
  } else {
    arguments.join("::")
  }
  project.resolve_module(@modulepath.ModulePath::root(), requested)
}

///|
/// Return a list response when `--default-list` or the selected module's
/// `default-list` setting applies. Explicit recipe invocations return `None`.
pub fn[
  F : @host.HostFs,
  T : @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] execute_default_list_command(
  host : F,
  terminal_host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse? raise ApplicationError {
  guard arguments.command() == RunCommand else { return None }
  let (arguments, context) = search_prefixed_invocation(arguments, context)
  let platform = @host.HostPlatform::platform_info(terminal_host) catch {
    error => raise Host(error)
  }
  let semantic_platform = semantic_target_platform(platform)
  let loading_environment = @host.HostEnv::env_entries(terminal_host) catch {
    error => raise Host(error)
  }
  let (graph, _) = load_graph_input_with_directories(
    host,
    arguments,
    context,
    platform=semantic_platform,
    environment=loading_environment,
  )
  let project = compile_loaded_graph(
    graph,
    allow_unstable=arguments.flag("unstable"),
    platform=semantic_platform,
  )
  guard default_list_module_path(project, arguments.positional()) is Some(path) else {
    return None
  }
  let compilation = project.module_compilation(path).unwrap()
  if !arguments.flag("default-list") &&
    !compilation.settings().bool("default-list") {
    return None
  }
  let color = match arguments.value("color").unwrap_or("auto") {
    "always" => true
    "never" => false
    "auto" => {
      let terminal = @host.HostTerminal::terminal_info(terminal_host) catch {
        error => raise Host(error)
      }
      terminal.color_supported() && terminal.stdout_is_terminal()
    }
    _ => raise Query("invalid --color value")
  }
  let builder = StringBuilder()
  builder.write_string(
    arguments.value("list-heading").unwrap_or("Available recipes:\n"),
  )
  let globals = evaluate_project_globals(project, arguments)
  append_project_list_module(
    builder, graph, project, path, arguments, color, 0, globals,
  )
  Some(
    @cli.ApplicationResponse::success(stdout=@utf8.encode(builder.to_string())),
  )
}

///|
/// Bounded-source variant used by the native and wasm CLI entry points.
#warnings("-unused_async-unused_trait_bound")
pub async fn[
  F : @host.HostFs + @host.HostSourceReader,
  T : @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] execute_default_list_command_async(
  host : F,
  terminal_host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse? raise ApplicationError {
  clear_prepared_run_project()
  guard arguments.command() == RunCommand else { return None }
  let (arguments, context) = search_prefixed_invocation(arguments, context)
  let platform = @host.HostPlatform::platform_info(terminal_host) catch {
    error => raise Host(error)
  }
  perf_detail_mark("run.preflight.platform")
  let semantic_platform = semantic_target_platform(platform)
  let loading_environment = @host.HostEnv::env_entries(terminal_host) catch {
    error => raise Host(error)
  }
  perf_detail_mark("run.preflight.environment")
  let (graph, directories) = load_graph_input_with_directories_async(
    host,
    arguments,
    context,
    platform=semantic_platform,
    environment=loading_environment,
  )
  perf_detail_mark("run.preflight.load")
  let project = compile_loaded_graph(
    graph,
    allow_unstable=arguments.flag("unstable"),
    platform=semantic_platform,
  )
  perf_detail_mark("run.preflight.compile")
  guard default_list_module_path(project, arguments.positional()) is Some(path) else {
    cache_prepared_run_project(
      arguments, context, platform, loading_environment, graph, directories, project,
    )
    return None
  }
  let compilation = project.module_compilation(path).unwrap()
  if !arguments.flag("default-list") &&
    !compilation.settings().bool("default-list") {
    cache_prepared_run_project(
      arguments, context, platform, loading_environment, graph, directories, project,
    )
    return None
  }
  let color = match arguments.value("color").unwrap_or("auto") {
    "always" => true
    "never" => false
    "auto" => {
      let terminal = @host.HostTerminal::terminal_info(terminal_host) catch {
        error => raise Host(error)
      }
      terminal.color_supported() && terminal.stdout_is_terminal()
    }
    _ => raise Query("invalid --color value")
  }
  let builder = StringBuilder()
  builder.write_string(
    arguments.value("list-heading").unwrap_or("Available recipes:\n"),
  )
  let globals = evaluate_project_globals(project, arguments)
  append_project_list_module(
    builder, graph, project, path, arguments, color, 0, globals,
  )
  Some(
    @cli.ApplicationResponse::success(stdout=@utf8.encode(builder.to_string())),
  )
}

///|
fn query_text(
  loaded : @loader.LoadedSource,
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
  color : Bool,
) -> String raise ApplicationError {
  match arguments.command() {
    ListCommand => list_text(loaded, compilation, arguments, color)
    ShowCommand => show_text(loaded, compilation, arguments)
    SummaryCommand =>
      visible_recipe_names(compilation, arguments).join(" ") + "\n"
    UsageCommand => usage_text(compilation, arguments)
    VariablesCommand => {
      let private = private_assignments(loaded.ast())
      let values : Array[String] = []
      for name in compilation.variable_names() {
        if !private.contains(name) {
          values.push(name)
        }
      }
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
fn[
  F : @host.HostFs,
  T : @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] execute_query_command_with_terminal(
  host : F,
  terminal_host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  let (arguments, context) = query_search_prefix(host, arguments, context)
  let platform = @host.HostPlatform::platform_info(terminal_host) catch {
    error => raise Host(error)
  }
  let semantic_platform = semantic_target_platform(platform)
  let loading_environment = @host.HostEnv::env_entries(terminal_host) catch {
    error => raise Host(error)
  }
  let (graph, _) = load_graph_input_with_directories(
    host,
    arguments,
    context,
    platform=semantic_platform,
    environment=loading_environment,
  )
  let project = compile_loaded_graph(
    graph,
    allow_unstable=arguments.flag("unstable"),
    platform=semantic_platform,
  )
  validate_project_variable_overrides(project, arguments)
  let color = match arguments.value("color").unwrap_or("auto") {
    "always" => true
    "never" => false
    "auto" => {
      let terminal = @host.HostTerminal::terminal_info(terminal_host) catch {
        error => raise Host(error)
      }
      terminal.color_supported() && terminal.stdout_is_terminal()
    }
    _ => raise Query("invalid --color value")
  }
  let output = query_project_text(graph, project, arguments, color)
  let stderr = if arguments.command() == SummaryCommand &&
    !arguments.flag("quiet") &&
    output == "\n" {
    b"justfile contains no recipes\n"
  } else {
    b""
  }
  @cli.ApplicationResponse::success(stdout=@utf8.encode(output), stderr~)
}

///|
pub fn[
  T : @host.HostFs + @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] execute_query_command(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  execute_query_command_with_terminal(host, host, arguments, context)
}

///|
#warnings("-unused_async-unused_trait_bound")
pub async fn[
  F : @host.HostFs + @host.HostSourceReader,
  T : @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] execute_query_command_with_terminal_async(
  host : F,
  terminal_host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  let (arguments, context) = query_search_prefix(host, arguments, context)
  let platform = @host.HostPlatform::platform_info(terminal_host) catch {
    error => raise Host(error)
  }
  perf_detail_mark("query.platform")
  let semantic_platform = semantic_target_platform(platform)
  let loading_environment = @host.HostEnv::env_entries(terminal_host) catch {
    error => raise Host(error)
  }
  perf_detail_mark("query.environment")
  let (graph, _) = load_graph_input_with_directories_async(
    host,
    arguments,
    context,
    platform=semantic_platform,
    environment=loading_environment,
  )
  perf_detail_mark("query.load")
  let project = compile_loaded_graph(
    graph,
    allow_unstable=arguments.flag("unstable"),
    platform=semantic_platform,
  )
  perf_detail_mark("query.compile")
  validate_project_variable_overrides(project, arguments)
  let color = match arguments.value("color").unwrap_or("auto") {
    "always" => true
    "never" => false
    "auto" => {
      let terminal = @host.HostTerminal::terminal_info(terminal_host) catch {
        error => raise Host(error)
      }
      terminal.color_supported() && terminal.stdout_is_terminal()
    }
    _ => raise Query("invalid --color value")
  }
  let output = query_project_text(graph, project, arguments, color)
  perf_detail_mark("query.render")
  ignore(perf_detail_emit() catch { _ => () })
  let stderr = if arguments.command() == SummaryCommand &&
    !arguments.flag("quiet") &&
    output == "\n" {
    b"justfile contains no recipes\n"
  } else {
    b""
  }
  @cli.ApplicationResponse::success(stdout=@utf8.encode(output), stderr~)
}
