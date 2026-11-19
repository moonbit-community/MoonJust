///|
/// Failures raised while discovering or reading justfiles.
#derive(Eq, Debug)
pub(all) suberror LoaderError {
  InvalidLimit
  NoJustfileFound(start~ : @path.PathValue)
  MissingSearchDirectory(@path.PathValue)
  AmbiguousJustfile(directory~ : @path.PathValue, found~ : Array[String])
  ExplicitFileMissing(path~ : @path.PathValue)
  SourceIsDirectory(@path.PathValue)
  ImportFileMissing(span~ : @source.Span, source~ : @source.Source)
  Host(@host.HostError)
  InvalidSource(@source.SourceError)
  Parse(@parser.ParserError, @source.Source)
  ImportCycle(
    path~ : @path.PathValue,
    chain~ : Array[@path.PathValue],
    span~ : @source.Span?,
  )
  ModuleFileMissing(
    module_name~ : String,
    span~ : @source.Span,
    source~ : @source.Source?,
  )
  AmbiguousModuleFile(
    module_name~ : String,
    found~ : Array[@path.PathValue],
    source~ : @source.Source?,
    span~ : @source.Span,
  )
}

///|
pub fn LoaderError::code(self : LoaderError) -> String {
  match self {
    InvalidLimit => "MJ-LOAD-0000"
    NoJustfileFound(_) => "MJ-LOAD-0001"
    MissingSearchDirectory(_) => "MJ-LOAD-0011"
    AmbiguousJustfile(_) => "MJ-LOAD-0009"
    ExplicitFileMissing(_) => "MJ-LOAD-0002"
    SourceIsDirectory(_) => "MJ-LOAD-0012"
    ImportFileMissing(_) => "MJ-LOAD-0010"
    Host(_) => "MJ-LOAD-0003"
    InvalidSource(_) => "MJ-LOAD-0004"
    Parse(_) => "MJ-LOAD-0005"
    ImportCycle(_) => "MJ-LOAD-0006"
    ModuleFileMissing(_) => "MJ-LOAD-0007"
    AmbiguousModuleFile(_) => "MJ-LOAD-0008"
  }
}

///|
pub fn LoaderError::span(self : LoaderError) -> @source.Span? {
  match self {
    InvalidLimit => None
    Parse(error, _) => Some(error.span())
    NoJustfileFound(_) => None
    MissingSearchDirectory(_) => None
    AmbiguousJustfile(_) => None
    ExplicitFileMissing(_) => None
    SourceIsDirectory(_) => None
    ImportFileMissing(span~, ..) => Some(span)
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
    SourceIsDirectory(path) => {
      let detail = if path.flavor() == Windows {
        "Access is denied. (os error 5)"
      } else {
        "Is a directory (os error 21)"
      }
      "failed to read justfile at `" + path.as_string() + "`: " + detail
    }
    ImportFileMissing(_) => "could not find source file for import"
    Host(_) => "host error while loading"
    InvalidSource(_) => "invalid source"
    Parse(error, _) => error.message()
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
    AmbiguousModuleFile(module_name~, found~, ..) =>
      "found multiple source files for module `" +
      module_name +
      "`: " +
      @diagnostic.join_list(
        found.map(path => path.as_string()),
        "and",
        ticked=true,
      )
  }
}

///|
/// The source retained by the loader at the failing parse or include site.
pub fn LoaderError::diagnostic_source(self : LoaderError) -> @source.Source? {
  match self {
    Parse(_, source) | ImportFileMissing(source~, ..) => Some(source)
    ModuleFileMissing(source~, ..) | AmbiguousModuleFile(source~, ..) => source
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
