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
    for
      name in @query.visible_recipe_names(
        compilation,
        @query.build_query(arguments),
      ) {
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
