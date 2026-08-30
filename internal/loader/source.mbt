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
