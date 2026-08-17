///|
/// Version of the stable JSON contract emitted by `--json` and JSON dump.
pub fn inspect_json_schema_version() -> Int {
  1
}

///|
fn json_object(entries : Array[(String, Json)]) -> Json {
  Json::object(Map::from_array(entries))
}

///|
fn json_strings(values : ArrayView[String]) -> Json {
  Json::array(values.map(Json::string))
}

///|
fn optional_json_string(value : String?) -> Json {
  match value {
    Some(value) => Json::string(value)
    None => Json::null()
  }
}

///|
fn unsigned_json(expression : @syntax.Expression?) -> Json {
  guard expression is Some(String(value)) else { return Json::null() }
  let text = value.cooked()
  let number = @string.parse_int(text[:]) catch { _ => return Json::null() }
  Json::number(number.to_double(), repr=text)
}

///|
fn pattern_json(expression : @syntax.Expression?) -> Json {
  match expression {
    Some(String(value)) => Json::array([Json::string(value.cooked())])
    Some(List(elements~, ..)) => Json::array(elements.map(attribute_plain_json))
    Some(value) => Json::array([attribute_plain_json(value)])
    None => Json::null()
  }
}

///|
fn expression_json(expression : @syntax.Expression) -> Json {
  match expression {
    String(value) => Json::string(value.cooked())
    Backtick(value) =>
      Json::array([Json::string("evaluate"), Json::string(value.cooked())])
    Boolean(value~, ..) => Json::boolean(value)
    Variable(name~, ..) =>
      Json::array([Json::string("variable"), Json::string(name)])
    Call(name~, arguments~, ..) => {
      let values : Array[Json] = [Json::string("call"), Json::string(name)]
      for argument in arguments {
        values.push(expression_json(argument))
      }
      Json::array(values)
    }
    List(elements~, ..) => {
      let values : Array[Json] = [Json::string("list")]
      for element in elements {
        values.push(expression_json(element))
      }
      Json::array(values)
    }
    Parenthesized(expression~, ..) => expression_json(expression)
    Unary(operator=Not, operand~, ..) =>
      Json::array([Json::string("not"), expression_json(operand)])
    Binary(operator~, lhs~, rhs~, ..) => {
      let name = match operator {
        Or => "or"
        And => "and"
        Equal => "=="
        NotEqual => "!="
        RegexMatch => "=~"
        RegexNotMatch => "!~"
        ListConcat => "list-concatenate"
        Concat => "concatenate"
        Join => "join"
      }
      Json::array([
        Json::string(name),
        expression_json(lhs),
        expression_json(rhs),
      ])
    }
    Conditional(condition~, then_branch~, else_branch~, ..) =>
      Json::array([
        Json::string("if"),
        expression_json(condition),
        expression_json(then_branch),
        match else_branch {
          Some(value) => expression_json(value)
          None => Json::null()
        },
      ])
    Format(start~, parts~, ..) => {
      let values : Array[Json] = [
        Json::string("format"),
        Json::string(start.cooked()),
      ]
      for part in parts {
        values.push(expression_json(part.expression()))
        values.push(Json::string(part.literal().cooked()))
      }
      Json::array(values)
    }
  }
}

///|
fn private_assignments(ast : @syntax.Ast) -> Set[String] {
  let result : Set[String] = Set([])
  for item in ast.items() {
    match item {
      Assignment(assignment) =>
        if assignment.name().has_prefix("_") ||
          assignment
          .attributes()
          .any(fn(attribute) { attribute.name() == "private" }) {
          result.add(assignment.name())
        }
      _ => ()
    }
  }
  result
}

///|
fn assignment_json(assignment : @syntax.Assignment, private : Bool) -> Json {
  json_object([
    ("eager", Json::boolean(assignment.eager())),
    ("export", Json::boolean(assignment.exported())),
    ("name", Json::string(assignment.name())),
    ("private", Json::boolean(private)),
    ("value", expression_json(assignment.value())),
  ])
}

///|
fn parameter_json(
  parameter : @syntax.Parameter,
  attributes : ArrayView[@syntax.Attribute],
) -> Json {
  let mut help : Json = Json::null()
  let mut flag = false
  let mut long : Json = Json::null()
  let mut max : Json = Json::null()
  let mut min : Json = Json::null()
  let mut multiple = false
  let mut pattern : Json = Json::null()
  let mut short : Json = Json::null()
  let mut value : Json = Json::null()
  for attribute in attributes {
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
          help = argument.value().map(expression_json).unwrap_or(Json::null())
        Some("long") =>
          long = argument
            .value()
            .map(expression_json)
            .unwrap_or(Json::string(parameter.name()))
        Some("max") => max = unsigned_json(argument.value())
        Some("min") => min = unsigned_json(argument.value())
        Some("multiple") => multiple = true
        Some("pattern") => pattern = pattern_json(argument.value())
        Some("short") =>
          short = argument
            .value()
            .map(expression_json)
            .unwrap_or(Json::string(parameter.name()))
        Some("value") =>
          value = argument
            .value()
            .map(expression_json)
            .unwrap_or(Json::boolean(true))
        _ => ()
      }
    }
  }
  json_object([
    (
      "default",
      match parameter.default_value() {
        Some(value) => expression_json(value)
        None => Json::null()
      },
    ),
    ("export", Json::boolean(parameter.exported())),
    ("flag", Json::boolean(flag)),
    ("help", help),
    (
      "kind",
      Json::string(
        if parameter.variadic() {
          if parameter.variadic_minimum() == 0 {
            "star"
          } else {
            "plus"
          }
        } else {
          "singular"
        },
      ),
    ),
    ("long", long),
    ("max", max),
    ("min", min),
    ("multiple", Json::boolean(multiple)),
    ("name", Json::string(parameter.name())),
    ("pattern", pattern),
    ("short", short),
    ("value", value),
  ])
}

///|
fn dependency_json(dependency : @syntax.Dependency) -> Json {
  json_object([
    ("arguments", Json::array(dependency.arguments().map(expression_json))),
    ("recipe", Json::string(dependency.name())),
    (
      "star",
      if dependency.starred() {
        Json::number(0.0, repr="0")
      } else {
        Json::null()
      },
    ),
  ])
}

///|
fn attribute_plain_json(expression : @syntax.Expression) -> Json {
  match expression {
    List(elements~, ..) => Json::array(elements.map(attribute_plain_json))
    _ => expression_json(expression)
  }
}

///|
fn attribute_json(attribute : @syntax.Attribute) -> Json {
  if attribute.name() == "arg" {
    let arguments = attribute.arguments()
    let mut name : Json = Json::null()
    let mut help : Json = Json::null()
    let mut long : Json = Json::null()
    let mut max : Json = Json::null()
    let mut min : Json = Json::null()
    let mut pattern : Json = Json::null()
    let mut short : Json = Json::null()
    let mut value : Json = Json::null()
    guard arguments.get(0) is Some(first_argument) else {
      return Json::string("arg")
    }
    guard first_argument.value() is Some(first) else {
      return Json::string("arg")
    }
    name = attribute_plain_json(first)
    for argument in arguments[1:] {
      match argument.key() {
        Some("help") =>
          help = argument
            .value()
            .map(attribute_plain_json)
            .unwrap_or(Json::boolean(true))
        Some("long") =>
          long = argument.value().map(attribute_plain_json).unwrap_or(name)
        Some("max") => max = unsigned_json(argument.value())
        Some("min") => min = unsigned_json(argument.value())
        Some("pattern") => pattern = pattern_json(argument.value())
        Some("short") =>
          short = argument.value().map(attribute_plain_json).unwrap_or(name)
        Some("value") =>
          value = argument
            .value()
            .map(attribute_plain_json)
            .unwrap_or(Json::boolean(true))
        _ => ()
      }
    }
    return json_object([
      (
        "arg",
        json_object([
          ("help", help),
          ("long", long),
          ("max", max),
          ("min", min),
          ("name", name),
          ("pattern", pattern),
          ("short", short),
          ("value", value),
        ]),
      ),
    ])
  }
  if attribute.name() == "continue" || attribute.name() == "metadata" {
    let values : Array[Json] = []
    for argument in attribute.arguments() {
      match argument.value() {
        Some(value) => values.push(attribute_plain_json(value))
        None => ()
      }
    }
    if attribute.name() == "continue" {
      values.sort_by(fn(left, right) {
        lexical_compare(left.stringify(), right.stringify())
      })
    }
    return json_object([(attribute.name(), Json::array(values))])
  }
  let arguments = attribute.arguments()
  if arguments.is_empty() {
    return Json::string(attribute.name())
  }
  let positional : Array[Json] = []
  let keyword : Array[(String, Json)] = []
  for argument in arguments {
    let value = match argument.value() {
      Some(value) => expression_json(value)
      None => Json::null()
    }
    match argument.key() {
      Some(key) => keyword.push((key, value))
      None => positional.push(value)
    }
  }
  let value = if !keyword.is_empty() {
    json_object(keyword)
  } else if positional.length() == 1 {
    positional[0]
  } else {
    Json::array(positional)
  }
  json_object([(attribute.name(), value)])
}

///|
fn recipe_json(
  recipe : @syntax.Recipe,
  compilation : @semantic.Compilation,
  docs : Map[String, String],
  module_path : @modulepath.ModulePath,
) -> Json {
  let attribute_nodes = recipe.attributes().to_owned()
  attribute_nodes.sort_by(fn(left, right) {
    lexical_compare(left.name(), right.name())
  })
  let attributes = attribute_nodes.map(attribute_json)
  let body : Array[Json] = []
  for line in recipe.lines() {
    let fragments : Array[Json] = []
    for fragment in line.fragments() {
      match fragment {
        Text(text~, ..) => fragments.push(Json::string(text))
        Interpolation(expression~, ..) =>
          fragments.push(Json::array([expression_json(expression)]))
      }
    }
    body.push(Json::array(fragments))
  }
  let dependencies : Array[Json] = []
  for dependency in recipe.dependencies() {
    dependencies.push(dependency_json(dependency))
  }
  for dependency in recipe.subsequent_dependencies() {
    dependencies.push(dependency_json(dependency))
  }
  let parameters : Array[Json] = []
  for parameter in recipe.parameters() {
    parameters.push(parameter_json(parameter, recipe.attributes()))
  }
  let semantic_attributes = compilation.recipe_attributes(recipe.name())
  let doc : String? = match semantic_attributes {
    Some(value) =>
      match value.doc() {
        Some(doc) => Some(doc)
        None => docs.get(recipe.name())
      }
    None => docs.get(recipe.name())
  }
  let private = semantic_attributes
    .map(fn(value) { value.private() || recipe.name().has_prefix("_") })
    .unwrap_or(recipe.name().has_prefix("_"))
  let mut shebang = recipe
    .attributes()
    .any(fn(attribute) { attribute.name() == "script" })
  match recipe.lines().get(0) {
    Some(line) =>
      match line.fragments().get(0) {
        Some(Text(text~, ..)) if text.has_prefix("#!") => shebang = true
        _ => ()
      }
    None => ()
  }
  json_object([
    ("attributes", Json::array(attributes)),
    ("body", Json::array(body)),
    ("dependencies", Json::array(dependencies)),
    ("doc", optional_json_string(doc)),
    ("name", Json::string(recipe.name())),
    ("parameters", Json::array(parameters)),
    (
      "priors",
      Json::number(
        recipe.dependencies().length().to_double(),
        repr=recipe.dependencies().length().to_string(),
      ),
    ),
    ("private", Json::boolean(private)),
    ("quiet", Json::boolean(recipe.quiet())),
    (
      "namepath",
      Json::string(
        if module_path.is_root() {
          recipe.name()
        } else {
          module_path.as_string() + "::" + recipe.name()
        },
      ),
    ),
    ("shebang", Json::boolean(shebang)),
  ])
}

///|
fn setting_json(settings : @semantic.CompiledSettings, name : String) -> Json {
  match settings.get(name) {
    Some(Boolean(value)) => Json::boolean(value)
    Some(Flag) => Json::boolean(true)
    Some(Text(value)) => Json::string(value)
    Some(Expression(value)) => expression_json(value)
    None => Json::null()
  }
}

///|
fn setting_list_json(
  settings : @semantic.CompiledSettings,
  name : String,
) -> Json {
  match settings.get(name) {
    Some(Text(value)) => Json::array([Json::string(value)])
    Some(Expression(List(elements~, ..))) =>
      Json::array(elements.map(attribute_plain_json))
    Some(Expression(value)) => Json::array([attribute_plain_json(value)])
    _ => Json::array([])
  }
}

///|
fn interpreter_json(
  settings : @semantic.CompiledSettings,
  name : String,
) -> Json {
  guard settings.get(name) is Some(Expression(List(elements~, ..))) else {
    return Json::null()
  }
  guard elements.get(0) is Some(command) else { return Json::null() }
  json_object([
    ("command", attribute_plain_json(command)),
    ("arguments", Json::array(elements[1:].map(attribute_plain_json))),
  ])
}

///|
fn setting_scalar_or_list_json(
  settings : @semantic.CompiledSettings,
  name : String,
) -> Json {
  match settings.get(name) {
    Some(Expression(List(elements~, ..))) =>
      Json::array(elements.map(attribute_plain_json))
    _ => setting_json(settings, name)
  }
}

///|
fn settings_json(settings : @semantic.CompiledSettings) -> Json {
  json_object([
    (
      "allow_duplicate_recipes",
      Json::boolean(settings.bool("allow-duplicate-recipes")),
    ),
    (
      "allow_duplicate_variables",
      Json::boolean(settings.bool("allow-duplicate-variables")),
    ),
    ("default_list", Json::boolean(settings.bool("default-list"))),
    ("default_script", Json::boolean(settings.bool("default-script"))),
    ("dotenv_command", setting_list_json(settings, "dotenv-command")),
    (
      "dotenv_filename",
      setting_scalar_or_list_json(settings, "dotenv-filename"),
    ),
    ("dotenv_load", Json::boolean(settings.bool("dotenv-load"))),
    ("dotenv_override", Json::boolean(settings.bool("dotenv-override"))),
    ("dotenv_path", setting_scalar_or_list_json(settings, "dotenv-path")),
    ("dotenv_required", Json::boolean(settings.bool("dotenv-required"))),
    ("export", Json::boolean(settings.bool("export"))),
    ("fallback", Json::boolean(settings.bool("fallback"))),
    ("guards", Json::boolean(settings.bool("guards"))),
    ("ignore_comments", Json::boolean(settings.bool("ignore-comments"))),
    ("indentation", setting_json(settings, "indentation")),
    ("lazy", Json::boolean(settings.bool("lazy"))),
    ("lists", Json::boolean(settings.bool("lists"))),
    ("no_cd", Json::boolean(settings.bool("no-cd"))),
    ("no_exit_message", Json::boolean(settings.bool("no-exit-message"))),
    (
      "positional_arguments",
      Json::boolean(settings.bool("positional-arguments")),
    ),
    ("quiet", Json::boolean(settings.bool("quiet"))),
    ("shell", interpreter_json(settings, "shell")),
    ("tempdir", setting_json(settings, "tempdir")),
    ("unstable", Json::boolean(settings.bool("unstable"))),
    ("windows_powershell", Json::boolean(settings.bool("windows-powershell"))),
    ("windows_shell", setting_json(settings, "windows-shell")),
    ("working_directory", setting_json(settings, "working-directory")),
  ])
}

///|
fn inspect_json(
  loaded : @loader.LoadedSource,
  compilation : @semantic.Compilation,
  module_path? : @modulepath.ModulePath = @modulepath.ModulePath::root(),
  project? : @semantic.ProjectCompilation,
  graph? : @loader.LoadedGraph,
) -> Json {
  let private = private_assignments(loaded.ast())
  let assignment_entries : Array[(String, Json)] = []
  let names = compilation.variable_names().to_owned()
  names.sort_by(lexical_compare)
  for name in names {
    guard compilation.variable(name) is Some(assignment) else { continue }
    assignment_entries.push(
      (name, assignment_json(assignment, private.contains(name))),
    )
  }
  let alias_entries : Array[(String, Json)] = []
  for symbol in compilation.symbols() {
    if symbol.kind() is Alias {
      guard compilation.alias_target(symbol.name()) is Some(target) else {
        continue
      }
      alias_entries.push(
        (
          symbol.name(),
          json_object([
            ("attributes", Json::array([])),
            ("name", Json::string(symbol.name())),
            ("target", Json::string(target)),
          ]),
        ),
      )
    }
  }
  alias_entries.sort_by(fn(left, right) { lexical_compare(left.0, right.0) })
  let docs = recipe_docs(loaded.ast())
  let recipe_entries : Array[(String, Json)] = []
  let source_recipe_names = compilation.recipe_names()
  let first = source_recipe_names.get(0)
  let recipe_names = source_recipe_names.to_owned()
  recipe_names.sort_by(lexical_compare)
  for name in recipe_names {
    guard compilation.recipe(name) is Some(recipe) else { continue }
    recipe_entries.push(
      (name, recipe_json(recipe, compilation, docs, module_path)),
    )
  }
  let unexports : Array[String] = []
  for item in loaded.ast().items() {
    if item is Unexport(name~, ..) {
      unexports.push(name)
    }
  }
  unexports.sort_by(lexical_compare)
  let module_entries : Array[(String, Json)] = []
  match (project, graph) {
    (Some(project), Some(graph)) => {
      for child in project.module_paths() {
        if child.parent() != Some(module_path) {
          continue
        }
        guard project.module_compilation(child) is Some(child_compilation) else {
          continue
        }
        let mut child_loaded : @loader.LoadedSource? = None
        for candidate in graph.files() {
          if candidate.module_path() == child &&
            (
              candidate.relation() == RootSource ||
              candidate.relation() == ModuleSource
            ) {
            child_loaded = Some(candidate)
            break
          }
        }
        guard child_loaded is Some(child_loaded) else { continue }
        let child_name = child.components().last().unwrap()
        module_entries.push(
          (
            child_name,
            inspect_json(
              child_loaded,
              child_compilation,
              module_path=child,
              project~,
              graph~,
            ),
          ),
        )
      }
      module_entries.sort_by(fn(left, right) {
        lexical_compare(left.0, right.0)
      })
    }
    _ => ()
  }
  let mut module_doc = if module_path.is_root() {
    None
  } else {
    project
    .map(fn(value) { value.module_declaration_doc(module_path) })
    .unwrap_or(None)
  }
  let module_groups : Array[String] = []
  match project {
    Some(project) if !module_path.is_root() =>
      for attribute in project.module_declaration_attributes(module_path) {
        if attribute.name() == "doc" {
          guard attribute.arguments().get(0) is Some(argument) else { continue }
          if argument.value() is Some(String(value)) {
            module_doc = Some(value.cooked())
          }
        } else if attribute.name() == "group" {
          guard attribute.arguments().get(0) is Some(argument) else { continue }
          if argument.value() is Some(String(value)) &&
            !module_groups.contains(value.cooked()) {
            module_groups.push(value.cooked())
          }
        }
      }
    _ => ()
  }
  json_object([
    ("assignments", json_object(assignment_entries)),
    ("first", optional_json_string(first)),
    ("doc", optional_json_string(module_doc)),
    ("groups", json_strings(module_groups)),
    ("module_path", Json::string(module_path.as_string())),
    ("modules", json_object(module_entries)),
    ("aliases", json_object(alias_entries)),
    ("recipes", json_object(recipe_entries)),
    ("settings", settings_json(compilation.settings())),
    ("source", Json::string(loaded.canonical_path().as_string())),
    ("unexports", json_strings(unexports)),
    ("warnings", Json::array([])),
  ])
}

///|
fn shell_escape(value : String) -> String {
  let builder = StringBuilder()
  for character in value {
    if character == '!' ||
      character == '"' ||
      character == '$' ||
      character == '\\' ||
      character == '`' {
      builder.write_char('\\')
    }
    builder.write_char(character)
  }
  builder.to_string()
}

///|
fn joined_value(value : @value.Value) -> String {
  value.to_string()
}

///|
fn just_value(value : @value.Value) -> String {
  value.display()
}

///|
fn colored_just_value(value : @value.Value) -> String {
  let text = value.display()
  let characters = text.to_array()
  let builder = StringBuilder()
  builder.write_string("\u{001b}[32m")
  let mut index = 0
  while index < characters.length() {
    if characters[index] == '\\' && index + 1 < characters.length() {
      builder.write_string("\u{001b}[36m")
      builder.write_char(characters[index])
      builder.write_char(characters[index + 1])
      builder.write_string("\u{001b}[32m")
      index += 2
    } else {
      builder.write_char(characters[index])
      index += 1
    }
  }
  builder.write_string("\u{001b}[0m")
  builder.to_string()
}

///|
fn evaluate_text(
  compilation : @semantic.Compilation,
  ast : @syntax.Ast,
  arguments : @cli.CliArguments,
) -> String raise ApplicationError {
  let environment = @evaluator.LazyEnvironment::new(compilation)
  let overrides = variable_overrides(compilation, arguments)
  environment.apply_overrides(overrides) catch {
    error => raise Evaluation(error)
  }
  match arguments.positional().get(0) {
    Some(name) =>
      joined_value(
        environment.resolve(name) catch {
          error => raise Evaluation(error)
        },
      )
    None => {
      let private = private_assignments(ast)
      let names = compilation.variable_names().to_owned()
      names.sort_by(lexical_compare)
      let mut maximum = 0
      for name in names {
        if !private.contains(name) {
          maximum = Int::max(maximum, name.length())
        }
      }
      let builder = StringBuilder()
      let shell = arguments.value("evaluate-format") == Some("shell")
      for name in names {
        if private.contains(name) {
          continue
        }
        let value = environment.resolve(name) catch {
          error => raise Evaluation(error)
        }
        if shell {
          guard compilation.variable(name) is Some(assignment) else { continue }
          if assignment.exported() || compilation.settings().bool("export") {
            builder.write_string("export ")
          }
          builder.write_string(name.replace(old="-", new="_"))
          builder.write_string("=\"")
          builder.write_string(shell_escape(joined_value(value)))
          builder.write_string("\"\n")
        } else {
          builder.write_string(name)
          for _ in name.length()..<maximum {
            builder.write_char(' ')
          }
          builder.write_string(" := ")
          builder.write_string(
            if arguments.value("color") == Some("always") {
              colored_just_value(value)
            } else {
              just_value(value)
            },
          )
          builder.write_char('\n')
        }
      }
      builder.to_string()
    }
  }
}

///|
fn evaluated_environment_text(
  compilation : @semantic.Compilation,
  ast : @syntax.Ast,
  arguments : @cli.CliArguments,
  environment : @evaluator.Environment,
  selected? : String,
) -> String raise ApplicationError {
  match selected {
    Some(name) =>
      match environment.get(name) {
        Some(value) => joined_value(value)
        None => raise Query("variable `" + name + "` is not defined")
      }
    None => {
      let private = private_assignments(ast)
      let names = compilation.variable_names().to_owned()
      names.sort_by(lexical_compare)
      let mut maximum = 0
      for name in names {
        if !private.contains(name) {
          maximum = Int::max(maximum, name.length())
        }
      }
      let builder = StringBuilder()
      let shell = arguments.value("evaluate-format") == Some("shell")
      for name in names {
        if private.contains(name) {
          continue
        }
        guard environment.get(name) is Some(value) else { continue }
        if shell {
          guard compilation.variable(name) is Some(assignment) else { continue }
          if assignment.exported() || compilation.settings().bool("export") {
            builder.write_string("export ")
          }
          builder.write_string(name.replace(old="-", new="_"))
          builder.write_string("=\"")
          builder.write_string(shell_escape(joined_value(value)))
          builder.write_string("\"\n")
        } else {
          builder.write_string(name)
          for _ in name.length()..<maximum {
            builder.write_char(' ')
          }
          builder.write_string(" := ")
          builder.write_string(
            if arguments.value("color") == Some("always") {
              colored_just_value(value)
            } else {
              just_value(value)
            },
          )
          builder.write_char('\n')
        }
      }
      builder.to_string()
    }
  }
}

///|
fn evaluation_path(
  project : @semantic.ProjectCompilation,
  arguments : ArrayView[String],
) -> (@modulepath.ModulePath, String?) raise ApplicationError {
  if arguments.is_empty() {
    return (@modulepath.ModulePath::root(), None)
  }
  if arguments.length() != 1 {
    raise Query(
      "`--evaluate` used with unexpected argument: `" + arguments[1] + "`",
    )
  }
  let requested = arguments[0]
  let root = @modulepath.ModulePath::root()
  if project.root().variable(requested) is Some(_) {
    return (root, Some(requested))
  }
  match project.resolve_module(root, requested) {
    Some(path) => return (path, None)
    None => ()
  }
  let full = @modulepath.ModulePath::parse(requested) catch {
    _ => raise Query("invalid evaluation path `" + arguments[0] + "`")
  }
  let components = full.components().to_owned()
  guard components.pop() is Some(name) else {
    return (@modulepath.ModulePath::root(), None)
  }
  if components.is_empty() {
    let names = project.root().variable_names().to_owned()
    names.append(direct_submodule_names(project, root))
    let base = "justfile does not contain variable or submodule `" + name + "`"
    raise Query(
      match closest_name(name, names) {
        Some(suggestion) => base + "\nDid you mean `" + suggestion + "`?"
        None => base
      },
    )
  }
  let parent = components.join("::")
  if project.absent_module_for_reference(root, parent) is Some(absent) {
    raise Query("optional module `" + absent.as_string() + "` is absent")
  }
  let path = match project.resolve_module(root, parent) {
    Some(path) => path
    None =>
      raise Query(
        unknown_submodule_message(project, root, components[0], display=parent),
      )
  }
  (path, Some(name))
}

///|
pub async fn[
  F : @host.HostFs + @host.HostSourceReader,
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] execute_evaluate_command_async(
  filesystem : F,
  effects : H,
  process : P,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  if arguments.command() != EvaluateCommand {
    raise UnsupportedCommand("async evaluation for non-evaluate command")
  }
  let loading_environment = @host.HostEnv::env_entries(effects) catch {
    error => raise Host(error)
  }
  let (graph, directories) = load_graph_input_with_directories_async(
    filesystem,
    arguments,
    context,
    environment=loading_environment,
  )
  let platform = @host.HostPlatform::platform_info(effects) catch {
    error => raise Host(error)
  }
  let project = compile_loaded_graph(
    graph,
    allow_unstable=arguments.flag("unstable"),
    platform=semantic_target_platform(platform),
  )
  let (path, selected) = evaluation_path(project, arguments.positional())
  let (globals, _) = evaluate_project_globals_async(
    filesystem,
    process,
    effects,
    project,
    directories,
    arguments,
    platform,
    evaluation_target=(path, selected),
  )
  guard project.module_compilation(path) is Some(compilation) else {
    raise Query("unknown module `" + path.as_string() + "`")
  }
  guard loaded_for_module(graph, path) is Some(loaded) else {
    raise Query("source for module `" + path.as_string() + "` is unavailable")
  }
  let output = evaluated_environment_text(
    compilation,
    loaded.ast(),
    arguments,
    globals[path],
    selected?,
  )
  @cli.ApplicationResponse::success(stdout=@utf8.encode(output))
}

///|
pub fn[T : @host.HostFs] execute_inspect_command(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
  environment? : ArrayView[(String, String)] = [],
) -> @cli.ApplicationResponse raise ApplicationError {
  let (graph, _) = load_graph_input_with_directories(
    host,
    arguments,
    context,
    environment~,
  )
  let loaded = graph.files()[0]
  let project = compile_loaded_graph(
    graph,
    allow_unstable=arguments.flag("unstable"),
  )
  let compilation = project.root()
  let output = match arguments.command() {
    EvaluateCommand => evaluate_text(compilation, loaded.ast(), arguments)
    DumpCommand if arguments.value("dump-format") == Some("json") =>
      inspect_json(loaded, compilation, project~, graph~).stringify() + "\n"
    DumpCommand => {
      let indentation = formatting_indentation(arguments, loaded.ast())
      @formatter.format_with_indentation(loaded.ast(), indentation) catch {
        error => raise Format(error)
      }
    }
    JsonCommand =>
      inspect_json(loaded, compilation, project~, graph~).stringify() + "\n"
    command => raise UnsupportedCommand("\{Repr(command)}")
  }
  @cli.ApplicationResponse::success(stdout=@utf8.encode(output))
}

///|
pub async fn[T : @host.HostFs + @host.HostSourceReader] execute_inspect_command_async(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
  environment? : ArrayView[(String, String)] = [],
) -> @cli.ApplicationResponse raise ApplicationError {
  let (graph, _) = load_graph_input_with_directories_async(
    host,
    arguments,
    context,
    environment~,
  )
  let loaded = graph.files()[0]
  let project = compile_loaded_graph(
    graph,
    allow_unstable=arguments.flag("unstable"),
  )
  let compilation = project.root()
  let output = match arguments.command() {
    EvaluateCommand => evaluate_text(compilation, loaded.ast(), arguments)
    DumpCommand if arguments.value("dump-format") == Some("json") =>
      inspect_json(loaded, compilation, project~, graph~).stringify() + "\n"
    DumpCommand => {
      let indentation = formatting_indentation(arguments, loaded.ast())
      @formatter.format_with_indentation(loaded.ast(), indentation) catch {
        error => raise Format(error)
      }
    }
    JsonCommand =>
      inspect_json(loaded, compilation, project~, graph~).stringify() + "\n"
    command => raise UnsupportedCommand("\{Repr(command)}")
  }
  @cli.ApplicationResponse::success(stdout=@utf8.encode(output))
}
