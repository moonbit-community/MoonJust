///|
/// Failures raised while discovering or reading justfiles.
pub(all) suberror LoaderError {
  InvalidLimit
  NoJustfileFound(start~ : @path.PathValue, filename~ : String)
  ExplicitFileMissing(path~ : @path.PathValue)
  Host(@host.HostError)
  InvalidSource(@source.SourceError)
  Parse(@parser.ParserError)
  ImportCycle(path~ : @path.PathValue)
} derive(Eq, Debug)

///|
pub fn LoaderError::code(self : LoaderError) -> String {
  match self {
    InvalidLimit => "MJ-LOAD-0000"
    NoJustfileFound(_) => "MJ-LOAD-0001"
    ExplicitFileMissing(_) => "MJ-LOAD-0002"
    Host(_) => "MJ-LOAD-0003"
    InvalidSource(_) => "MJ-LOAD-0004"
    Parse(_) => "MJ-LOAD-0005"
    ImportCycle(_) => "MJ-LOAD-0006"
  }
}

///|
pub fn LoaderError::span(self : LoaderError) -> @source.Span? {
  match self {
    InvalidLimit => None
    Parse(error) => Some(error.span())
    NoJustfileFound(_)
    | ExplicitFileMissing(_)
    | Host(_)
    | InvalidSource(_)
    | ImportCycle(_) => None
  }
}

///|
pub fn LoaderError::message(self : LoaderError) -> String {
  match self {
    InvalidLimit => "invalid loader limit"
    NoJustfileFound(start~, filename~) =>
      "no `" + filename + "` found from " + start.as_string()
    ExplicitFileMissing(path~) =>
      "explicit justfile is missing: " + path.as_string()
    Host(_) => "host error while loading"
    InvalidSource(_) => "invalid source"
    Parse(error) => error.message()
    ImportCycle(path~) => "import cycle includes " + path.as_string()
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
    "load error",
  )
}
