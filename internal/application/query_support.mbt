///|
/// Project compilation is owned by `internal/project`; application only maps
/// its domain error into the response-oriented application error.
fn compile_loaded_graph(
  graph : @loader.LoadedGraph,
  allow_unstable? : Bool = false,
  platform? : @semantic.TargetPlatform = @semantic.TargetPlatform::new(
    Other("unknown"),
    false,
  ),
) -> @semantic.ProjectCompilation raise ApplicationError {
  @project.compile_loaded_graph(graph, allow_unstable~, platform~) catch {
    Load(error) => raise Load(error)
    Path(error) => raise Path(error)
    WorkingDirectory(error) => raise WorkingDirectory(error)
    Semantic(error) => raise Semantic(error)
    Compilation(error) => raise Project(error)
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
  names.sort_by(@query.lexical_compare)
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
  result.sort_by(@query.lexical_compare)
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
