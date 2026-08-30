///|
priv struct GraphNodeKey {
  canonical_path : @path.PathValue
  module_path : @modulepath.ModulePath
} derive(Eq, Hash)

///|
/// Load imports and modules recursively from an already parsed root.
fn[T : @host.HostFs] build_graph(
  host : T,
  root_source : LoadedSource,
  source_id : @source.SourceId,
  limits : GraphLimits,
  platform : @semantic.TargetPlatform,
  environment : ArrayView[(String, String)],
) -> LoadedGraph raise LoaderError {
  let root = root_source.path()
  let files : Array[LoadedSource] = []
  let source_cache : Map[String, Bytes] = Map([])
  let canonical_cache : Map[String, @path.PathValue] = Map([])
  let metadata_cache : Map[String, @host.FileMetadata] = Map([])
  let active : Set[GraphNodeKey] = Set([])
  let active_paths : Set[@path.PathValue] = Set([])
  let visited : Set[GraphNodeKey] = Set([])
  let active_stack : Array[@path.PathValue] = []
  fn visit(
    path : @path.PathValue,
    next_id : @source.SourceId,
    parent : @path.PathValue?,
    import_span : @source.Span?,
    relation : SourceRelation,
    module_path : @modulepath.ModulePath,
    module_directory : @path.PathValue,
  ) -> Unit raise LoaderError {
    let canonical = if parent is None {
      root_source.canonical_path()
    } else {
      let key = path.as_string()
      match canonical_cache.get(key) {
        Some(value) => value
        None => {
          let value = @host.HostFs::canonicalize(host, path) catch {
            error => raise Host(error)
          }
          canonical_cache[key] = value
          value
        }
      }
    }
    let key = { canonical_path: canonical, module_path, }
    if active.contains(key) || active_paths.contains(canonical) {
      raise ImportCycle(path~, chain=active_stack.copy(), span=import_span)
    }
    if visited.contains(key) {
      return
    }
    if files.length() >= limits.max_files {
      raise Host(InvalidInput("import graph file limit exceeded"))
    }
    active.add(key)
    active_paths.add(canonical)
    active_stack.push(path)
    let loaded = if parent is None {
      root_source.with_context(
        parent, import_span, relation, module_path, module_directory,
      )
    } else {
      let parent_directory = source_directory(parent.unwrap())
      let parent_key = parent_directory.as_string()
      let canonical_parent_directory = match canonical_cache.get(parent_key) {
        Some(value) => value
        None => {
          let value = @host.HostFs::canonicalize(host, parent_directory) catch {
            error => raise Host(error)
          }
          canonical_cache[parent_key] = value
          value
        }
      }
      let source_path = if path_is_within(canonical_parent_directory, canonical) {
        path
      } else {
        canonical
      }
      load_cached(
        host, source_path, canonical, next_id, source_cache, environment,
      ).with_context(
        parent, import_span, relation, module_path, module_directory,
      )
    }
    files.push(loaded)
    let mut pending_attributes : Array[@syntax.Attribute] = []
    for item in loaded.ast().items() {
      match item {
        Attribute(value) => {
          pending_attributes.push(value)
          continue
        }
        Import(value) => {
          let enabled = @semantic.platform_attributes_match(
            pending_attributes, platform,
          )
          pending_attributes = []
          if !enabled {
            continue
          }
          let child = import_path(path, value.path(), environment~)
          let exists = @host.HostFs::file_exists(host, child) catch {
            error => raise Host(error)
          }
          if exists || !value.optional() {
            if !exists {
              raise ImportFileMissing(span=value.path().span())
            }
            visit(
              child,
              @source.SourceId::new(next_id.value() + files.length()),
              Some(path),
              Some(value.span()),
              ImportedSource,
              module_path,
              module_directory,
            )
          }
        }
        Module(value) => {
          pending_attributes = []
          if !@semantic.platform_attributes_match(value.attributes(), platform) {
            continue
          }
          match
            resolve_module_file(
              host,
              path,
              value,
              environment~,
              metadata_cache~,
            ) {
            None => ()
            Some(child) =>
              visit(
                child,
                @source.SourceId::new(next_id.value() + files.length()),
                Some(path),
                Some(value.span()),
                ModuleSource,
                module_path.child(value.name()) catch {
                  _ => raise Host(InvalidInput("invalid module name"))
                },
                source_directory(child),
              )
          }
        }
        _ => pending_attributes = []
      }
    }
    active.remove(key)
    active_paths.remove(canonical)
    active_stack.pop() |> ignore
    visited.add(key)
  }
  visit(
    root,
    source_id,
    None,
    None,
    RootSource,
    @modulepath.ModulePath::root(),
    source_directory(root),
  )
  { files, }
}

///|
/// Load imports and modules recursively, preserving source order and detecting cycles.
pub fn[T : @host.HostFs] load_graph(
  host : T,
  root : @path.PathValue,
  source_id : @source.SourceId,
  limits? : GraphLimits = GraphLimits::default(),
  platform? : @semantic.TargetPlatform = @semantic.TargetPlatform::new(
    Other("unknown"),
    false,
  ),
  environment? : ArrayView[(String, String)] = [],
) -> LoadedGraph raise LoaderError {
  build_graph(
    host,
    load(host, root, source_id, environment~),
    source_id,
    limits,
    platform,
    environment,
  )
}

///|
/// Load a stdin root while resolving imports and modules relative to `base`.
pub fn[T : @host.HostFs] load_stdin_graph(
  host : T,
  bytes : Bytes,
  source_id : @source.SourceId,
  base : @path.PathValue,
  limits? : GraphLimits = GraphLimits::default(),
  platform? : @semantic.TargetPlatform = @semantic.TargetPlatform::new(
    Other("unknown"),
    false,
  ),
  environment? : ArrayView[(String, String)] = [],
) -> LoadedGraph raise LoaderError {
  let loaded = load_stdin(bytes, source_id, environment~)
  let name = @path.PathValue::new("<stdin>", base.flavor()) catch {
    _ => raise Host(InvalidInput("invalid stdin graph path"))
  }
  let path = base.join(name) catch {
    _ => raise Host(InvalidInput("stdin graph path flavor mismatch"))
  }
  let root = {
    path,
    canonical_path: path,
    source: loaded.source(),
    ast: loaded.ast(),
    parent: None,
    import_span: None,
    relation: RootSource,
    module_path: @modulepath.ModulePath::root(),
    module_directory: base,
  }
  build_graph(host, root, source_id, limits, platform, environment)
}
