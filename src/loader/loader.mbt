///|
/// Search policy for a justfile lookup.
pub(all) struct SearchOptions {
  filename : String
  ceiling : @path.PathValue?
  explicit : @path.PathValue?
  global : @path.PathValue?
} derive(Eq, Debug)

///|
pub fn SearchOptions::new(
  filename? : String = "justfile",
  ceiling? : @path.PathValue? = None,
  explicit? : @path.PathValue? = None,
  global? : @path.PathValue? = None,
) -> SearchOptions {
  { filename, ceiling, explicit, global, }
}

///|
pub fn SearchOptions::filename(self : SearchOptions) -> String {
  self.filename
}

///|
pub fn SearchOptions::ceiling(self : SearchOptions) -> @path.PathValue? {
  self.ceiling
}

///|
pub fn SearchOptions::explicit(self : SearchOptions) -> @path.PathValue? {
  self.explicit
}

///|
pub fn SearchOptions::global(self : SearchOptions) -> @path.PathValue? {
  self.global
}

///|
/// How a source entered the load graph. Imports retain their containing
/// module's working directory, while modules establish a new one.
pub(all) enum SourceRelation {
  RootSource
  ImportedSource
  ModuleSource
} derive(Eq, Debug)

///|
pub(all) struct LoadedSource {
  path : @path.PathValue
  canonical_path : @path.PathValue
  source : @source.Source
  ast : @syntax.Ast
  parent : @path.PathValue?
  import_span : @source.Span?
  relation : SourceRelation
  module_path : @modulepath.ModulePath
  module_directory : @path.PathValue
} derive(Debug)

///|
/// A deterministic depth-first import/module load result.
pub struct LoadedGraph {
  files : Array[LoadedSource]
} derive(Debug)

///|
pub fn LoadedGraph::files(self : LoadedGraph) -> ArrayView[LoadedSource] {
  self.files[:]
}

///|
pub(all) struct GraphLimits {
  max_files : Int
} derive(Eq, Debug)

///|
pub fn GraphLimits::default() -> GraphLimits {
  { max_files: 256, }
}

///|
pub fn GraphLimits::new(max_files : Int) -> GraphLimits raise LoaderError {
  if max_files <= 0 {
    raise InvalidLimit
  }
  { max_files, }
}

///|
pub fn LoadedSource::path(self : LoadedSource) -> @path.PathValue {
  self.path
}

///|
pub fn LoadedSource::canonical_path(self : LoadedSource) -> @path.PathValue {
  self.canonical_path
}

///|
pub fn LoadedSource::source(self : LoadedSource) -> @source.Source {
  self.source
}

///|
pub fn LoadedSource::ast(self : LoadedSource) -> @syntax.Ast {
  self.ast
}

///|
pub fn LoadedSource::parent(self : LoadedSource) -> @path.PathValue? {
  self.parent
}

///|
pub fn LoadedSource::import_span(self : LoadedSource) -> @source.Span? {
  self.import_span
}

///|
pub fn LoadedSource::relation(self : LoadedSource) -> SourceRelation {
  self.relation
}

///|
pub fn LoadedSource::module_path(self : LoadedSource) -> @modulepath.ModulePath {
  self.module_path
}

///|
pub fn LoadedSource::module_directory(self : LoadedSource) -> @path.PathValue {
  self.module_directory
}

///|
fn source_directory(path : @path.PathValue) -> @path.PathValue {
  path.parent().unwrap_or(path)
}

///|
fn path_is_within(directory : @path.PathValue, path : @path.PathValue) -> Bool {
  if directory.flavor() != path.flavor() {
    return false
  }
  let base = directory.as_string()
  if path.as_string() == base {
    return true
  }
  let separator = directory.flavor().separator().to_string()
  let prefix = if base.has_suffix(separator) { base } else { base + separator }
  path.as_string().has_prefix(prefix)
}

///|
fn LoadedSource::with_context(
  self : LoadedSource,
  parent : @path.PathValue?,
  import_span : @source.Span?,
  relation : SourceRelation,
  module_path : @modulepath.ModulePath,
  module_directory : @path.PathValue,
) -> LoadedSource {
  {
    path: self.path,
    canonical_path: self.canonical_path,
    source: self.source,
    ast: self.ast,
    parent,
    import_span,
    relation,
    module_path,
    module_directory,
  }
}

///|
/// Load source supplied by stdin or another non-filesystem transport.
pub fn load_stdin(
  bytes : Bytes,
  source_id : @source.SourceId,
  display_name? : String = "<stdin>",
  environment? : ArrayView[(String, String)] = [],
) -> LoadedSource raise LoaderError {
  let source = @source.Source::from_bytes(source_id, display_name, bytes) catch {
    error => raise InvalidSource(error)
  }
  let ast = parse_loaded_source(source, environment~)
  let path = @path.PathValue::new(display_name, Unix) catch {
    _ => raise Host(InvalidInput("invalid stdin display name"))
  }
  {
    path,
    canonical_path: path,
    source,
    ast,
    parent: None,
    import_span: None,
    relation: RootSource,
    module_path: @modulepath.ModulePath::root(),
    module_directory: source_directory(path),
  }
}

///|
fn parse_loaded_source(
  source : @source.Source,
  environment? : ArrayView[(String, String)] = [],
) -> @syntax.Ast raise LoaderError {
  @parser.parse_with_environment(source, environment) catch {
    error =>
      raise ParseSource(
        error,
        source_name=source.name(),
        source_bytes=source.bytes().to_owned(),
      )
  }
}

///|
fn parent_or_self(path : @path.PathValue) -> @path.PathValue? {
  path.parent()
}

///|
fn lower_ascii(value : String) -> String {
  let builder = StringBuilder()
  for character in value {
    if character.is_ascii_uppercase() {
      builder.write_char((character.to_int() + 32).to_char().unwrap())
    } else {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
fn filename_lexical_compare(left : String, right : String) -> Int {
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
/// Return whether a filesystem input uses the Markdown justfile extension.
pub fn is_markdown_path(path : @path.PathValue) -> Bool {
  match path.extension() {
    Some(extension) => lower_ascii(extension) == "md"
    None => false
  }
}

///|
fn source_from_file_bytes(
  bytes : Bytes,
  source_id : @source.SourceId,
  path : @path.PathValue,
) -> @source.Source raise LoaderError {
  let source = @source.Source::from_bytes(source_id, path.as_string(), bytes) catch {
    error => raise InvalidSource(error)
  }
  if is_markdown_path(path) {
    (@formatter.tangle(source) catch {
      _ => raise Host(InvalidInput("invalid Markdown source"))
    }).source()
  } else {
    source
  }
}

///|
fn[T : @host.HostFs] find_candidate(
  host : T,
  directory : @path.PathValue,
  filename : String,
) -> @path.PathValue? raise LoaderError {
  let entries = @host.HostFs::read_dir(host, directory) catch {
    error => raise Host(error)
  }
  let expected = lower_ascii(filename)
  let found : Array[String] = []
  for entry in entries {
    if lower_ascii(entry) == expected ||
      (filename == "justfile" && lower_ascii(entry) == ".justfile") {
      let child = @path.PathValue::new(entry, directory.flavor()) catch {
        _ => raise Host(InvalidInput("invalid directory entry"))
      }
      let path = directory.join(child) catch {
        _ => raise Host(InvalidInput("path flavor mismatch"))
      }
      let exists = @host.HostFs::file_exists(host, path) catch {
        error => raise Host(error)
      }
      if exists {
        found.push(entry)
      }
    }
  }
  found.sort_by(filename_lexical_compare)
  if found.length() > 1 {
    raise AmbiguousJustfile(directory~, found~)
  }
  match found.get(0) {
    Some(name) => {
      let child = @path.PathValue::new(name, directory.flavor()) catch {
        _ => raise Host(InvalidInput("invalid directory entry"))
      }
      Some(
        directory.join(child) catch {
          _ => raise Host(InvalidInput("path flavor mismatch"))
        },
      )
    }
    None => None
  }
}

///|
/// Discover a justfile without consulting global process state.
pub fn[T : @host.HostFs] discover(
  host : T,
  start : @path.PathValue,
  options? : SearchOptions = SearchOptions::new(),
) -> @path.PathValue raise LoaderError {
  match options.explicit() {
    Some(path) => {
      let exists = @host.HostFs::file_exists(host, path) catch {
        error => raise Host(error)
      }
      if !exists {
        raise ExplicitFileMissing(path~)
      }
      return path
    }
    None => ()
  }
  let mut current = start
  while true {
    match find_candidate(host, current, options.filename()) {
      Some(path) => return path
      None => ()
    }
    match options.ceiling() {
      Some(ceiling) if current == ceiling => break
      _ => ()
    }
    match parent_or_self(current) {
      None => break
      Some(parent) if parent == current => break
      Some(parent) => current = parent
    }
  }
  match options.global() {
    Some(global) => {
      let exists = @host.HostFs::file_exists(host, global) catch {
        error => raise Host(error)
      }
      if exists {
        return global
      }
    }
    None => ()
  }
  raise NoJustfileFound(start~, filename=options.filename())
}

///|
/// Read and parse an already-discovered justfile through HostFs only.
pub fn[T : @host.HostFs] load(
  host : T,
  path : @path.PathValue,
  source_id : @source.SourceId,
  environment? : ArrayView[(String, String)] = [],
) -> LoadedSource raise LoaderError {
  let bytes = @host.HostFs::read_file(host, path) catch {
    error => raise Host(error)
  }
  let source = source_from_file_bytes(bytes, source_id, path)
  let ast = parse_loaded_source(source, environment~)
  let canonical_path = @host.HostFs::canonicalize(host, path) catch {
    error => raise Host(error)
  }
  {
    path,
    canonical_path,
    source,
    ast,
    parent: None,
    import_span: None,
    relation: RootSource,
    module_path: @modulepath.ModulePath::root(),
    module_directory: source_directory(path),
  }
}

///|
/// Reuse bytes during one graph load. Markdown is intentionally excluded: its
/// loaded source is the tangled representation rather than the raw file.
fn[T : @host.HostFs] load_cached(
  host : T,
  path : @path.PathValue,
  canonical : @path.PathValue,
  source_id : @source.SourceId,
  cache : Map[String, Bytes],
  environment : ArrayView[(String, String)],
) -> LoadedSource raise LoaderError {
  if is_markdown_path(path) {
    return load(host, path, source_id, environment~)
  }
  let key = canonical.as_string()
  match cache.get(key) {
    Some(bytes) => {
      let source = source_from_file_bytes(bytes, source_id, path)
      let ast = parse_loaded_source(source, environment~)
      {
        path,
        canonical_path: canonical,
        source,
        ast,
        parent: None,
        import_span: None,
        relation: RootSource,
        module_path: @modulepath.ModulePath::root(),
        module_directory: source_directory(path),
      }
    }
    None => {
      // Keep the first read on the established loader path. Besides retaining
      // exact error ordering, this avoids changing host behavior for module
      // candidates whose canonical path is only a planning hint.
      let loaded = load(host, path, source_id, environment~)
      cache[key] = loaded.source().bytes().to_owned()
      loaded
    }
  }
}

///|
/// Load an in-memory source through the same parser boundary as filesystem input.
pub fn load_bytes(
  bytes : Bytes,
  source_id : @source.SourceId,
  display_name : String,
  environment? : ArrayView[(String, String)] = [],
) -> LoadedSource raise LoaderError {
  let path = @path.PathValue::new(display_name, Unix) catch {
    _ => raise Host(InvalidInput("invalid source display name"))
  }
  let source = source_from_file_bytes(bytes, source_id, path)
  let ast = parse_loaded_source(source, environment~)
  {
    path,
    canonical_path: path,
    source,
    ast,
    parent: None,
    import_span: None,
    relation: RootSource,
    module_path: @modulepath.ModulePath::root(),
    module_directory: source_directory(path),
  }
}

///|
/// Load a Markdown source after source-aware fenced-just tangling.
pub fn load_markdown(
  bytes : Bytes,
  source_id : @source.SourceId,
  display_name? : String = "README.md",
  environment? : ArrayView[(String, String)] = [],
) -> LoadedSource raise LoaderError {
  let raw = @source.Source::from_bytes(source_id, display_name, bytes) catch {
    error => raise InvalidSource(error)
  }
  let tangled = @formatter.tangle(raw) catch {
    _ => raise Host(InvalidInput("invalid Markdown source"))
  }
  let source = tangled.source()
  let ast = parse_loaded_source(source, environment~)
  let path = @path.PathValue::new(display_name, Unix) catch {
    _ => raise Host(InvalidInput("invalid Markdown display name"))
  }
  {
    path,
    canonical_path: path,
    source,
    ast,
    parent: None,
    import_span: None,
    relation: RootSource,
    module_path: @modulepath.ModulePath::root(),
    module_directory: source_directory(path),
  }
}

///|
/// Discover and load using the caller's current directory.
pub fn[T : @host.HostFs + @host.HostEnv] load_from_current_dir(
  host : T,
  source_id : @source.SourceId,
  options? : SearchOptions = SearchOptions::new(),
) -> LoadedSource raise LoaderError {
  let cwd = @host.HostEnv::current_dir(host) catch {
    error => raise Host(error)
  }
  let path = discover(host, cwd, options~)
  let environment = @host.HostEnv::env_entries(host) catch {
    error => raise Host(error)
  }
  load(host, path, source_id, environment~)
}

///|
fn import_path(
  parent : @path.PathValue,
  literal : @syntax.StringLiteral,
  environment? : ArrayView[(String, String)] = [],
) -> @path.PathValue raise LoaderError {
  let mut value = literal.cooked()
  if value.has_prefix("~/") || value.has_prefix("~\\") {
    let home_name = if parent.flavor() == Windows {
      "USERPROFILE"
    } else {
      "HOME"
    }
    for entry in environment {
      if entry.0 == home_name {
        value = entry.1 + value.view(start_offset=1).to_owned()
        break
      }
    }
  }
  let child = @path.PathValue::new(value, parent.flavor()) catch {
    _ => raise Host(InvalidInput("invalid import path"))
  }
  let directory = parent.parent().unwrap_or(parent)
  directory.join(child) catch {
    _ => raise Host(InvalidInput("import path flavor mismatch"))
  }
}

///|
/// Metadata is scoped to one graph load. Recipes execute after the graph is
/// discarded, so a file changed by a recipe can never be observed through it.
fn[T : @host.HostFs] metadata_cached(
  host : T,
  path : @path.PathValue,
  cache : Map[String, @host.FileMetadata],
) -> @host.FileMetadata raise LoaderError {
  let key = path.as_string()
  match cache.get(key) {
    Some(value) => value
    None => {
      let value = @host.HostFs::metadata(host, path) catch {
        error => raise Host(error)
      }
      cache[key] = value
      value
    }
  }
}

///|
fn[T : @host.HostFs] push_existing_module_candidate(
  host : T,
  candidates : Array[@path.PathValue],
  path : @path.PathValue,
  metadata_cache? : Map[String, @host.FileMetadata] = Map([]),
) -> Unit raise LoaderError {
  let exists = @host.HostFs::file_exists(host, path) catch {
    error => raise Host(error)
  }
  if !exists {
    return
  }
  let metadata = metadata_cached(host, path, metadata_cache)
  if !metadata.is_file() {
    return
  }
  let canonical = @host.HostFs::canonicalize(host, path) catch {
    error => raise Host(error)
  }
  for candidate in candidates {
    let existing = @host.HostFs::canonicalize(host, candidate) catch {
      error => raise Host(error)
    }
    if existing == canonical {
      return
    }
  }
  candidates.push(path)
}

///|
fn lowercase_ascii(value : String) -> String {
  let builder = StringBuilder()
  for character in value {
    if character.is_ascii_uppercase() {
      builder.write_char((character.to_int() + 32).to_char().unwrap())
    } else {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
fn[T : @host.HostFs] push_module_directory_candidates(
  host : T,
  candidates : Array[@path.PathValue],
  directory : @path.PathValue,
  metadata_cache? : Map[String, @host.FileMetadata] = Map([]),
) -> Unit raise LoaderError {
  let exists = @host.HostFs::file_exists(host, directory) catch {
    error => raise Host(error)
  }
  if exists {
    let metadata = try metadata_cached(host, directory, metadata_cache) catch {
      Host(NotFound(_)) => return
      error => raise error
    } noraise {
      value => value
    }
    if !metadata.is_directory() {
      return
    }
  }
  let entries = try @host.HostFs::read_dir(host, directory) catch {
    NotFound(_) => return
    error => raise Host(error)
  } noraise {
    values => values
  }
  for entry in entries {
    let normalized = lowercase_ascii(entry)
    if entry != "mod.just" &&
      normalized != "justfile" &&
      normalized != ".justfile" {
      continue
    }
    let child = @path.PathValue::new(entry, directory.flavor()) catch {
      _ => raise Host(InvalidInput("invalid module candidate"))
    }
    push_existing_module_candidate(
      host,
      candidates,
      directory.join(child) catch {
        _ => raise Host(InvalidInput("module candidate flavor mismatch"))
      },
      metadata_cache~,
    )
  }
}

///|
fn[T : @host.HostFs] resolve_module_file(
  host : T,
  source_path : @path.PathValue,
  definition : @syntax.Module,
  environment? : ArrayView[(String, String)] = [],
  metadata_cache? : Map[String, @host.FileMetadata] = Map([]),
) -> @path.PathValue? raise LoaderError {
  let directory = source_path.parent().unwrap_or(source_path)
  let candidates : Array[@path.PathValue] = []
  match definition.path() {
    Some(literal) => {
      let explicit = import_path(source_path, literal, environment~)
      push_existing_module_candidate(
        host,
        candidates,
        explicit,
        metadata_cache~,
      )
      if candidates.is_empty() {
        push_module_directory_candidates(
          host,
          candidates,
          explicit,
          metadata_cache~,
        )
      }
    }
    None => {
      let direct = @path.PathValue::new(
        definition.name() + ".just",
        directory.flavor(),
      ) catch {
        _ => raise Host(InvalidInput("invalid module candidate"))
      }
      push_existing_module_candidate(
        host,
        candidates,
        directory.join(direct) catch {
          _ => raise Host(InvalidInput("module candidate flavor mismatch"))
        },
        metadata_cache~,
      )
      let module_directory = directory.join(
        @path.PathValue::new(definition.name(), directory.flavor()) catch {
          _ => raise Host(InvalidInput("invalid module directory"))
        },
      ) catch {
        _ => raise Host(InvalidInput("module directory flavor mismatch"))
      }
      push_module_directory_candidates(
        host,
        candidates,
        module_directory,
        metadata_cache~,
      )
    }
  }
  if candidates.length() > 1 {
    raise AmbiguousModuleFile(
      module_name=definition.name(),
      found=candidates,
      span=definition.name_span(),
    )
  }
  match candidates.get(0) {
    Some(path) => Some(path)
    None if definition.optional() => None
    None =>
      raise ModuleFileMissing(
        module_name=definition.name(),
        span=@source.Span::new(
          definition.span().source_id(),
          definition.span().start_byte() +
          (if definition.optional() { 5 } else { 4 }),
          definition.span().start_byte() +
          (if definition.optional() { 5 } else { 4 }) +
          definition.name().length(),
        ) catch {
          _ => definition.span()
        },
      )
  }
}

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
