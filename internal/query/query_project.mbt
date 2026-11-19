///|
pub fn loaded_for_module(
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
) -> @modulepath.ModulePath raise QueryError {
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
) -> (@modulepath.ModulePath, String, String) raise QueryError {
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
) -> String? raise QueryError {
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
fn project_summary_names(
  project : @semantic.ProjectCompilation,
  filter : RecipeFilter,
) -> Array[String] {
  let names : Array[String] = []
  for path in project.module_paths() {
    let compilation = project.module_compilation(path).unwrap()
    for name in visible_recipe_names(compilation, filter) {
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
  names
}

///|
pub fn render(
  request : QueryRequest,
  graph : @loader.LoadedGraph,
  project : @semantic.ProjectCompilation,
  color : Bool,
  globals : Map[@modulepath.ModulePath, @evaluator.Environment],
) -> QueryResult raise QueryError {
  let output = match request {
    Summary(filter, quiet~) =>
      return summary_result(project_summary_names(project, filter), quiet)
    ListModule(target, options) => {
      let path = match target {
        Arguments(parts) => module_path_from_arguments(project, parts[:])
        Module(path) => path
      }
      if project.module_compilation(path) is None {
        raise Query("unknown module `" + path.as_string() + "`")
      }
      options.heading + list_body(graph, project, path, options, color, globals)
    }
    Show(path, recipe) => {
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
      show_recipe_text(graph, project, path, recipe)
    }
    Usage(path, recipe, display) =>
      usage_recipe_text(
        project.module_compilation(path).unwrap(),
        recipe,
        display,
        environment=globals[path],
      )
    Variables => {
      let private = private_assignments(graph.files()[0].ast())
      let names = project
        .root()
        .variable_names()
        .filter(fn(name) { !private.contains(name) })
      names.sort_by(lexical_compare)
      if names.is_empty() {
        ""
      } else {
        names.join(" ") + "\n"
      }
    }
    Groups(filter, prefix~) => {
      let compilation = project.root()
      let groups : Array[String] = []
      for name in visible_recipe_names(compilation, filter) {
        if compilation.recipe_attributes(name) is Some(attributes) {
          for group in attributes.groups() {
            if !groups.contains(group) {
              groups.push(group)
            }
          }
        }
      }
      if !filter.unsorted {
        groups.sort_by(lexical_compare)
      }
      if groups.is_empty() {
        ""
      } else {
        "Recipe groups:\n" +
        groups.map(fn(value) { prefix + value }).join("\n") +
        "\n"
      }
    }
  }
  QueryResult::new(stdout=@utf8.encode(output))
}
