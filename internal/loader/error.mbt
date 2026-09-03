///|
/// Failures raised while discovering or reading justfiles.
pub(all) suberror LoaderError {
  InvalidLimit
  NoJustfileFound(start~ : @path.PathValue, filename~ : String)
  MissingSearchDirectory(@path.PathValue)
  AmbiguousJustfile(directory~ : @path.PathValue, found~ : Array[String])
  ExplicitFileMissing(path~ : @path.PathValue)
  ImportFileMissing(span~ : @source.Span)
  Host(@host.HostError)
  InvalidSource(@source.SourceError)
  Parse(@parser.ParserError)
  ParseSource(@parser.ParserError, source_name~ : String, source_bytes~ : Bytes)
  ImportCycle(
    path~ : @path.PathValue,
    chain~ : Array[@path.PathValue],
    span~ : @source.Span?
  )
  ModuleFileMissing(module_name~ : String, span~ : @source.Span)
  AmbiguousModuleFile(
    module_name~ : String,
    found~ : Array[@path.PathValue],
    span~ : @source.Span
  )
} derive(Eq, Debug)

///|
pub fn LoaderError::code(self : LoaderError) -> String {
  match self {
    InvalidLimit => "MJ-LOAD-0000"
    NoJustfileFound(_) => "MJ-LOAD-0001"
    MissingSearchDirectory(_) => "MJ-LOAD-0011"
    AmbiguousJustfile(_) => "MJ-LOAD-0009"
    ExplicitFileMissing(_) => "MJ-LOAD-0002"
    ImportFileMissing(_) => "MJ-LOAD-0010"
    Host(_) => "MJ-LOAD-0003"
    InvalidSource(_) => "MJ-LOAD-0004"
    Parse(_) | ParseSource(_) => "MJ-LOAD-0005"
    ImportCycle(_) => "MJ-LOAD-0006"
    ModuleFileMissing(_) => "MJ-LOAD-0007"
    AmbiguousModuleFile(_) => "MJ-LOAD-0008"
  }
}

///|
pub fn LoaderError::span(self : LoaderError) -> @source.Span? {
  match self {
    InvalidLimit => None
    Parse(error) | ParseSource(error, ..) => Some(error.span())
    NoJustfileFound(_) => None
    MissingSearchDirectory(_) => None
    AmbiguousJustfile(_) => None
    ExplicitFileMissing(_) => None
    ImportFileMissing(span~) => Some(span)
    Host(_) => None
    InvalidSource(_) => None
    ImportCycle(span~, ..) => span
    ModuleFileMissing(span~, ..) => Some(span)
    AmbiguousModuleFile(span~, ..) => Some(span)
  }
}

///|
pub fn LoaderError::message(self : LoaderError) -> String {
  match self {
    InvalidLimit => "invalid loader limit"
    NoJustfileFound(_) => "no justfile found"
    MissingSearchDirectory(path) =>
      "I/O error at `" +
      path.as_string() +
      "`: No such file or directory (os error 2)"
    AmbiguousJustfile(directory~, found~) =>
      "multiple candidate justfiles found in `" +
      directory.as_string() +
      "`: " +
      @diagnostic.join_list(found, "and", ticked=true)
    ExplicitFileMissing(path~) =>
      "explicit justfile is missing: " + path.as_string()
    ImportFileMissing(_) => "could not find source file for import"
    Host(_) => "host error while loading"
    InvalidSource(_) => "invalid source"
    Parse(error) | ParseSource(error, ..) => error.message()
    ImportCycle(path~, chain~, ..) => {
      let parent = chain.last().unwrap_or(path)
      "import `" +
      path.as_string() +
      "` in `" +
      parent.as_string() +
      "` is circular"
    }
    ModuleFileMissing(module_name~, ..) =>
      "could not find source file for module `" + module_name + "`"
    AmbiguousModuleFile(module_name~, found~, ..) => {
      let directory_candidates : Array[String] = []
      let direct_candidates : Array[String] = []
      let separator = found
        .get(0)
        .map(fn(path) { path.flavor().separator().to_string() })
        .unwrap_or("/")
      for path in found {
        let filename = path.file_name().unwrap_or(path.as_string())
        let parent_is_module = match path.parent() {
          Some(parent) => parent.file_name() == Some(module_name)
          None => false
        }
        if filename == module_name + ".just" {
          direct_candidates.push(filename)
        } else if parent_is_module {
          directory_candidates.push(module_name + separator + filename)
        } else {
          directory_candidates.push(path.as_string())
        }
      }
      directory_candidates.sort_by(fn(left, right) {
        let left_hidden = left.has_suffix(separator + ".justfile")
        let right_hidden = right.has_suffix(separator + ".justfile")
        if left_hidden && !right_hidden {
          -1
        } else if !left_hidden && right_hidden {
          1
        } else {
          left.compare(right)
        }
      })
      direct_candidates.sort()
      directory_candidates.append(direct_candidates)
      "found multiple source files for module `" +
      module_name +
      "`: " +
      directory_candidates.map(fn(path) { "`" + path + "`" }).join(" and ")
    }
  }
}

///|
/// Recover the exact source that failed parsing so diagnostics do not need to
/// successfully parse the same file a second time.
pub fn LoaderError::diagnostic_source(self : LoaderError) -> @source.Source? {
  match self {
    ParseSource(error, source_name~, source_bytes~) =>
      Some(
        @source.Source::from_bytes(
          error.span().source_id(),
          source_name,
          source_bytes,
        ),
      ) catch {
        _ => None
      }
    _ => None
  }
}

///|
pub fn LoaderError::to_diagnostic(
  self : LoaderError,
  fallback : @source.Span,
) -> @diagnostic.Diagnostic raise @diagnostic.DiagnosticError {
  @diagnostic.Diagnostic::new(
    self.code(),
    Error,
    self.message(),
    self.span().unwrap_or(fallback),
    "",
  )
}
