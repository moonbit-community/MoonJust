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
  { filename, ceiling, explicit, global }
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
pub(all) struct LoadedSource {
  path : @path.PathValue
  source : @source.Source
  ast : @syntax.Ast
  parent : @path.PathValue?
  import_span : @source.Span?
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
  { max_files: 256 }
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
fn LoadedSource::with_parent(
  self : LoadedSource,
  parent : @path.PathValue?,
  import_span : @source.Span?,
) -> LoadedSource {
  { path: self.path, source: self.source, ast: self.ast, parent, import_span }
}

///|
/// Load source supplied by stdin or another non-filesystem transport.
pub fn load_stdin(
  bytes : Bytes,
  source_id : @source.SourceId,
  display_name? : String = "<stdin>",
) -> LoadedSource raise LoaderError {
  let source = @source.Source::from_bytes(source_id, display_name, bytes) catch {
    error => raise InvalidSource(error)
  }
  let ast = @parser.parse(source) catch { error => raise Parse(error) }
  let path = @path.PathValue::new(display_name, Unix) catch {
    _ => raise Host(InvalidInput("invalid stdin display name"))
  }
  { path, source, ast, parent: None, import_span: None }
}

///|
fn parent_or_self(path : @path.PathValue) -> @path.PathValue? {
  path.parent()
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
    let candidate = @path.PathValue::new(options.filename(), start.flavor()) catch {
      _ => raise Host(InvalidInput("invalid filename"))
    }
    let path = current.join(candidate) catch {
      _ => raise Host(InvalidInput("path flavor mismatch"))
    }
    let exists = @host.HostFs::file_exists(host, path) catch {
      error => raise Host(error)
    }
    if exists {
      return path
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
) -> LoadedSource raise LoaderError {
  let bytes = @host.HostFs::read_file(host, path) catch {
    error => raise Host(error)
  }
  let source = @source.Source::from_bytes(source_id, path.as_string(), bytes) catch {
    error => raise InvalidSource(error)
  }
  let ast = @parser.parse(source) catch { error => raise Parse(error) }
  { path, source, ast, parent: None, import_span: None }
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
  load(host, path, source_id)
}

///|
fn import_path(
  parent : @path.PathValue,
  literal : @syntax.StringLiteral,
) -> @path.PathValue raise LoaderError {
  let child = @path.PathValue::new(literal.cooked(), parent.flavor()) catch {
    _ => raise Host(InvalidInput("invalid import path"))
  }
  let directory = parent.parent().unwrap_or(parent)
  directory.join(child) catch {
    _ => raise Host(InvalidInput("import path flavor mismatch"))
  }
}

///|
/// Load imports and modules recursively, preserving source order and detecting cycles.
pub fn[T : @host.HostFs] load_graph(
  host : T,
  root : @path.PathValue,
  source_id : @source.SourceId,
  limits? : GraphLimits = GraphLimits::default(),
) -> LoadedGraph raise LoaderError {
  let files : Array[LoadedSource] = []
  let active : Set[@path.PathValue] = Set([])
  let visited : Set[@path.PathValue] = Set([])
  fn visit(
    path : @path.PathValue,
    next_id : @source.SourceId,
    parent : @path.PathValue?,
    import_span : @source.Span?,
  ) -> Unit raise LoaderError {
    if active.contains(path) {
      raise ImportCycle(path~)
    }
    if visited.contains(path) {
      return
    }
    if files.length() >= limits.max_files {
      raise Host(InvalidInput("import graph file limit exceeded"))
    }
    active.add(path)
    let loaded = load(host, path, next_id).with_parent(parent, import_span)
    files.push(loaded)
    for item in loaded.ast().items() {
      match item {
        Import(value) => {
          let child = import_path(path, value.path())
          let exists = @host.HostFs::file_exists(host, child) catch {
            error => raise Host(error)
          }
          if exists || !value.optional() {
            if !exists {
              raise ExplicitFileMissing(path=child)
            }
            visit(
              child,
              @source.SourceId::new(next_id.value() + files.length()),
              Some(path),
              Some(value.span()),
            )
          }
        }
        Module(value) =>
          match value.path() {
            None => ()
            Some(literal) => {
              let child = import_path(path, literal)
              let exists = @host.HostFs::file_exists(host, child) catch {
                error => raise Host(error)
              }
              if exists || !value.optional() {
                if !exists {
                  raise ExplicitFileMissing(path=child)
                }
                visit(
                  child,
                  @source.SourceId::new(next_id.value() + files.length()),
                  Some(path),
                  Some(value.span()),
                )
              }
            }
          }
        _ => ()
      }
    }
    active.remove(path)
    visited.add(path)
  }
  visit(root, source_id, None, None)
  { files, }
}
