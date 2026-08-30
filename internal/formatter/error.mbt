///|
pub(all) suberror FormatterError {
  Parse(@parser.ParserError)
  InvalidInput(String)
} derive(Eq, Debug)

///|
pub fn FormatterError::code(self : FormatterError) -> String {
  match self {
    Parse(_) => "MJ-FMT-0001"
    InvalidInput(_) => "MJ-FMT-0002"
  }
}

///|
pub fn FormatterError::message(self : FormatterError) -> String {
  match self {
    Parse(error) => error.message()
    InvalidInput(message) => message
  }
}

///|
pub fn FormatterError::span(self : FormatterError) -> @source.Span? {
  match self {
    Parse(error) => Some(error.span())
    InvalidInput(_) => None
  }
}

///|
pub fn FormatterError::to_diagnostic(
  self : FormatterError,
  source : @source.Source,
) -> @diagnostic.Diagnostic raise @diagnostic.DiagnosticError {
  let span = self.span().unwrap_or(source.eof_span())
  @diagnostic.Diagnostic::new(self.code(), Error, self.message(), span, "")
}
