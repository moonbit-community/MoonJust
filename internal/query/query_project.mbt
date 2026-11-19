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
fn query_path(
  arguments : ArrayView[String],
) -> (@modulepath.ModulePath, String) raise QueryError {
  let parts = match arguments {
    [arg] if arg.contains(" ") =>
      String::from_iter(
        arg.iter().map(fn(c) { if c.is_whitespace() { ' ' } else { c } }),
      )
      .split(" ")
      .filter(fn(part) { !part.is_empty() })
      .map(StringView::to_owned)
      .collect()
    _ => arguments.to_owned()
  }
  let display = parts.join(" ")
  let path = match parts {
    [arg] => {
      if arg.is_empty() || arg.has_suffix(":") {
        raise Query("invalid module path `" + display + "`")
      }
      @modulepath.ModulePath::parse(arg) catch {
        _ => raise Query("invalid module path `" + display + "`")
      }
    }
    _ =>
      @modulepath.ModulePath::new(parts) catch {
        _ => raise Query("invalid module path `" + arguments.join(" ") + "`")
      }
  }
  (path, display)
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
  overrides~ : Map[@modulepath.ModulePath, Array[(String, String)]] = Map([]),
) -> QueryResult raise QueryError {
  let values = match request {
    ListModule(_, _) | ModuleUsage(_, _, ..) | Usage(_, _, _) =>
      evaluate_metadata(project, overrides)
    _ => Map([])
  }
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
      options.heading + list_body(graph, project, path, options, color, values)
    }
    Show(path, recipe) => show_recipe_text(graph, project, path, recipe)
    Usage(path, name, display) => {
      let compilation = project.module_compilation(path).unwrap()
      guard project.resolve_recipe(path, name) is Some(target) else {
        raise Query(unknown_recipe_message(compilation, name))
      }
      let path = target.module_path()
      let recipe = project
        .module_compilation(path)
        .unwrap()
        .recipe(target.recipe_name())
        .unwrap()
      let usage = usage_recipe_text(
        recipe,
        display,
        values,
        color,
        in_module=false,
      )
      match compilation.alias_target(name) {
        Some(target) => "alias " + name + " := " + target + "\n" + usage
        None => usage
      }
    }
    ModuleUsage(path, prefix, unsorted~, quiet~) => {
      let compilation = project.module_compilation(path).unwrap()
      let names = visible_recipe_names(compilation, { groups: [], unsorted, }).filter(fn(
          name,
        ) {
          !project.recipe_disabled(path, name)
        },
      )
      if names.is_empty() {
        return QueryResult::new(
          stderr=if quiet { b"" } else { b"module contains no recipes\n" },
        )
      }
      let docs = module_recipe_comments(graph, path)
      let entries = []
      for name in names {
        let recipe = compilation.recipe(name).unwrap()
        let builder = StringBuilder()
        if recipe_metadata_doc(recipe, docs, values) is Some(doc) {
          for line in doc.replace_all(old="\r\n", new="\n").split("\n") {
            builder.write_string(
              "    " + paint("# " + line.to_owned(), "34", color) + "\n",
            )
          }
        }
        let display = if prefix.is_empty() { name } else { prefix + " " + name }
        builder.write_string(
          usage_recipe_text(recipe, display, values, color, in_module=true),
        )
        entries.push(builder.to_string())
      }
      paint("Usage:", "1;33", color) + "\n" + entries.join("\n")
    }
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
