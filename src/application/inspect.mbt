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
  let mut private_next = false
  for item in ast.items() {
    match item {
      Attribute(attribute) =>
        if attribute.name() == "private" {
          private_next = true
        }
      Assignment(assignment) => {
        if private_next || assignment.name().has_prefix("_") {
          result.add(assignment.name())
        }
        private_next = false
      }
      Comment(_) | Blank(_) => ()
      _ => private_next = false
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
fn parameter_json(parameter : @syntax.Parameter) -> Json {
  json_object([
    (
      "default",
      match parameter.default_value() {
        Some(value) => expression_json(value)
        None => Json::null()
      },
    ),
    ("export", Json::boolean(parameter.exported())),
    ("flag", Json::boolean(false)),
    ("help", Json::null()),
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
    ("long", Json::null()),
    ("max", Json::null()),
    ("min", Json::null()),
    ("multiple", Json::boolean(false)),
    ("name", Json::string(parameter.name())),
    ("pattern", Json::null()),
    ("short", Json::null()),
    ("value", Json::null()),
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
fn recipe_json(
  recipe : @syntax.Recipe,
  compilation : @semantic.Compilation,
  docs : Map[String, String],
) -> Json {
  let attributes = recipe
    .attributes()
    .map(fn(attribute) { Json::string(attribute.name()) })
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
  let parameters = recipe.parameters().map(parameter_json)
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
    .map(fn(value) { value.private() })
    .unwrap_or(recipe.name().has_prefix("_"))
  json_object([
    ("attributes", Json::array(attributes)),
    ("body", Json::array(body)),
    ("dependencies", Json::array(dependencies)),
    ("doc", optional_json_string(doc)),
    ("name", Json::string(recipe.name())),
    ("parameters", Json::array(parameters)),
    ("priors", Json::number(0.0, repr="0")),
    ("private", Json::boolean(private)),
    ("quiet", Json::boolean(recipe.quiet())),
    ("namepath", Json::string(recipe.name())),
    ("shebang", Json::boolean(false)),
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
    ("dotenv_command", Json::array([])),
    ("dotenv_filename", setting_json(settings, "dotenv-filename")),
    ("dotenv_load", Json::boolean(settings.bool("dotenv-load"))),
    ("dotenv_override", Json::boolean(settings.bool("dotenv-override"))),
    ("dotenv_path", setting_json(settings, "dotenv-path")),
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
    ("shell", setting_json(settings, "shell")),
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
  let recipe_names = compilation.recipe_names().to_owned()
  recipe_names.sort_by(lexical_compare)
  let groups : Set[String] = Set([])
  let mut first : String? = None
  for name in recipe_names {
    guard compilation.recipe(name) is Some(recipe) else { continue }
    guard compilation.recipe_attributes(name) is Some(attributes) else {
      continue
    }
    if first is None && !attributes.private() {
      first = Some(name)
    }
    match attributes.group() {
      Some(group) => groups.add(group)
      None => ()
    }
    recipe_entries.push((name, recipe_json(recipe, compilation, docs)))
  }
  let group_values = groups.to_array()
  group_values.sort_by(lexical_compare)
  let unexports : Array[String] = []
  for item in loaded.ast().items() {
    if item is Unexport(name~, ..) {
      unexports.push(name)
    }
  }
  unexports.sort_by(lexical_compare)
  json_object([
    ("assignments", json_object(assignment_entries)),
    ("first", optional_json_string(first)),
    ("doc", Json::null()),
    ("groups", json_strings(group_values)),
    ("module_path", Json::string("")),
    ("modules", json_object([])),
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
  match value {
    String(value) => value
    Bool(value) => if value { "true" } else { "false" }
    List(values) => values.map(joined_value).join("")
  }
}

///|
fn just_value(value : @value.Value) -> String {
  match value {
    String(value) =>
      "\"" +
      value.replace(old="\\", new="\\\\").replace(old="\"", new="\\\"") +
      "\""
    Bool(value) => if value { "true" } else { "false" }
    List(values) => "[" + values.map(just_value).join(", ") + "]"
  }
}

///|
fn evaluate_text(
  compilation : @semantic.Compilation,
  ast : @syntax.Ast,
  arguments : @cli.CliArguments,
) -> String raise ApplicationError {
  let environment = @evaluator.LazyEnvironment::new(compilation)
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
          builder.write_string(just_value(value))
          builder.write_char('\n')
        }
      }
      builder.to_string()
    }
  }
}

///|
pub fn[T : @host.HostFs] execute_inspect_command(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  let loaded = load_input(host, arguments, context)
  let compilation = compile_loaded(loaded)
  let output = match arguments.command() {
    EvaluateCommand => evaluate_text(compilation, loaded.ast(), arguments)
    DumpCommand if arguments.value("dump-format") == Some("json") =>
      inspect_json(loaded, compilation).stringify() + "\n"
    DumpCommand => @formatter.format(loaded.ast())
    JsonCommand => inspect_json(loaded, compilation).stringify() + "\n"
    command => raise UnsupportedCommand("\{Repr(command)}")
  }
  @cli.ApplicationResponse::success(stdout=@utf8.encode(output))
}
