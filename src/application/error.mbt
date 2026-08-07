///|
/// Failures raised while composing pure packages with explicit host input.
pub(all) suberror ApplicationError {
  Cli(@cli.CliParseError)
  Load(@loader.LoaderError)
  Format(@formatter.FormatterError)
  Host(@host.HostError)
  Path(@path.PathError)
  AlreadyExists(@path.PathValue)
  UnsupportedCommand(String)
} derive(Debug)

///|
pub fn ApplicationError::exit_code(self : ApplicationError) -> Int {
  match self {
    Cli(_) | UnsupportedCommand(_) => 2
    Load(_) | Format(_) | Host(_) | Path(_) | AlreadyExists(_) => 1
  }
}

///|
pub fn ApplicationError::message(self : ApplicationError) -> String {
  match self {
    Cli(Invalid(message)) => message
    Cli(Unsupported(name)) => "error: option '\{name}' is not supported yet"
    Load(error) => "error[\{error.code()}]: \{error.message()}"
    Format(error) => "error[\{error.code()}]: \{error.message()}"
    Host(error) => "error: host operation failed: \{Repr(error)}"
    Path(error) => "error: invalid path: \{Repr(error)}"
    AlreadyExists(path) => "error: refusing to overwrite '\{path.as_string()}'"
    UnsupportedCommand(name) => "error: command '\{name}' is not supported yet"
  }
}
