///|
#derive(Debug)
pub(all) suberror ProjectError {
  Load(@loader.LoaderError)
  Path(@path.PathError)
  WorkingDirectory(@workdir.WorkingDirectoryError)
  Semantic(@semantic.SemanticError)
  Compilation(@semantic.ProjectCompilationError)
}

///|
fn module_items(
  graph : @loader.LoadedGraph,
  owner : Int32,
) -> (Array[@syntax.Item], Array[@semantic.ImportSource]) {
  let files = graph.files()
  let depths : Map[Int32, Int32] = Map([])
  let postorder = []
  // The upstream compiler fixes a file's depth and import path when it first
  // pops that file. A repeated import can reach it at a different depth.
  fn visit(index : Int32, depth : Int32) -> Unit {
    if depths.contains(index) {
      return
    }
    depths[index] = depth
    for child in graph.imports_from(index).rev_iter() {
      visit(child, depth + 1)
    }
    postorder.push(index)
  }
  visit(owner, 0)
  let items : Array[@syntax.Item] = []
  for index in postorder.rev_iter() {
    for item in files[index].ast().items() {
      match item {
        Import(_) =>
          while items.last() is Some(Attribute(_)) {
            ignore(items.pop())
          }
        Module(_) => ()
        _ => items.push(item)
      }
    }
  }
  // The analyzer schedules a file once, when it sees the import. Its stack
  // determines the tie-breaker, while listings retain textual import order.
  let imports : Array[@semantic.ImportSource] = []
  let stack = [owner]
  let scheduled = Set([owner])
  while stack.pop() is Some(index) {
    let file = files[index]
    imports.push({
      source: file.source(),
      depth: depths[index],
      items: file.ast().items(),
    })
    for child in graph.imports_from(index) {
      if !scheduled.contains(child) {
        scheduled.add(child)
        stack.push(child)
      }
    }
  }
  (items, imports)
}

///|
fn declaration_metadata(
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
            pending_docs.push(trimmed[2:].to_owned())
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
fn validate_names(
  files : ArrayView[@loader.LoadedSource],
  platform : @semantic.TargetPlatform,
) -> Unit raise ProjectError {
  let definitions : Map[String, (String, @source.Span)] = Map([])
  for loaded in files {
    let prefix = loaded.module_path().as_string() + "\u{0000}"
    for item in loaded.ast().items() {
      let entry : (String, String, @source.Span)? = match item {
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
            Some((definition.name(), "module", definition.name_span()))
          } else {
            None
          }
        }
        Recipe(recipe) if @semantic.platform_attributes_match(
            recipe.attributes(),
            platform,
          ) => Some((recipe.name(), "recipe", recipe.name_span))
        Alias(definition) if @semantic.platform_attributes_match(
            definition.attributes(),
            platform,
          ) => Some((definition.name(), "alias", definition.name_span))
        _ => None
      }
      guard entry is Some((name, kind, span)) else { continue }
      let key = prefix + name
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
fn default_recipe(compilation : @semantic.Compilation) -> String? {
  let first = compilation.recipe_names().get(0).map(fn(name) { name })
  for name in compilation.recipe_names() {
    match compilation.recipe_attributes(name) {
      Some(attributes) if attributes.names().contains("default") =>
        return Some(name)
      _ => ()
    }
  }
  first
}

///|
fn compile_root(
  loaded : @loader.LoadedSource,
  allow_unstable : Bool,
  platform : @semantic.TargetPlatform,
) -> @semantic.ProjectCompilation? raise ProjectError {
  for item in loaded.ast().items() {
    match item {
      Import(_) | Module(_) => return None
      _ => ()
    }
  }
  let compilation = @semantic.compile(
    loaded.ast(),
    platform~,
    allow_unstable~,
    defer_recipe_linking=true,
  ) catch {
    error => raise Semantic(error)
  }
  let source_file = loaded.path()
  let project = @semantic.ProjectCompilation::new([
    @semantic.ProjectModule::new(
      @modulepath.ModulePath::root(),
      compilation,
      loaded.module_directory(),
      source_file~,
      source_files=[(loaded.source().id(), source_file)],
      default_recipe?=default_recipe(compilation),
    ),
  ]) catch {
    error => raise Compilation(error)
  }
  @semantic.validate_project_compilation(project) catch {
    error => raise Semantic(error)
  }
  Some(project)
}

///|
pub fn compile_loaded_graph(
  graph : @loader.LoadedGraph,
  allow_unstable~ : Bool = false,
  platform~ : @semantic.TargetPlatform = @semantic.TargetPlatform::new(
    Other("unknown"),
    false,
  ),
) -> @semantic.ProjectCompilation raise ProjectError {
  let entries : Array[@semantic.ProjectModule] = []
  let absent_modules : Array[@modulepath.ModulePath] = []
  let files = graph.files()
  if files.length() == 1 && files[0].relation() == RootSource {
    match compile_root(files[0], allow_unstable, platform) {
      Some(project) => return project
      None => ()
    }
  }
  validate_names(files, platform)
  for index, loaded in files {
    if loaded.relation() != RootSource && loaded.relation() != ModuleSource {
      continue
    }
    let (items, imports) = module_items(graph, index)
    let ast = @syntax.Ast::new(
      loaded.ast().source_id(),
      items,
      loaded.ast().span(),
    )
    let compilation = @semantic.compile(
      ast,
      imports~,
      platform~,
      allow_unstable~,
      defer_recipe_linking=true,
    ) catch {
      error => raise Semantic(error)
    }
    let (attributes, doc, name_span) = declaration_metadata(files, loaded)
    let source_files : Array[(@source.SourceId, @path.PathValue)] = []
    for source in files {
      if source.module_path() == loaded.module_path() {
        source_files.push((source.ast().source_id(), source.path()))
      }
    }
    let mut selected_default : String? = None
    for item in loaded.ast().items() {
      guard item is Recipe(recipe) &&
        compilation.recipe(recipe.name()) is Some(_) else {
        continue
      }
      if selected_default is None {
        selected_default = Some(recipe.name())
      }
      if recipe
        .attributes()
        .any(fn(attribute) { attribute.name() == "default" }) {
        selected_default = Some(recipe.name())
        break
      }
    }
    for attribute in attributes {
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
            span=name_span.unwrap_or(
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
        declaration_attributes=attributes,
        declaration_doc?=doc,
        default_recipe?=selected_default,
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
    error => raise Compilation(error)
  }
  @semantic.validate_project_compilation(project) catch {
    error => raise Semantic(error)
  }
  project
}
