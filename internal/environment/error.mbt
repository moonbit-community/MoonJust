///|
/// Dotenv failures never retain a source line or parsed value. This keeps both
/// rendered and structural diagnostics safe for secret-bearing input.
pub(all) suberror DotenvError {
  InvalidUtf8(path~ : @path.PathValue)
  Parse(line~ : Int, column~ : Int)
  ParseFile(path~ : @path.PathValue, line~ : Int, column~ : Int)
  HostDenied(@host.HostCapability)
  HostUnavailable(@host.HostCapability)
  SourceAccess
  InvalidPath
  Required
  ArgumentsRequireLists
  CommandUnavailable(index~ : Int)
  CommandFailed(index~ : Int, exit_code~ : Int)
} derive(Eq, Debug)

///|
pub fn DotenvError::message(self : DotenvError) -> String {
  match self {
    InvalidUtf8(path~) =>
      "failed to load environment file from `\{path.as_string()}`: input is not valid UTF-8"
    Parse(line~, column~) =>
      "failed to parse environment entry at line \{line}, column \{column}"
    ParseFile(path~, line~, column~) =>
      "failed to load environment file from `" +
      path.as_string() +
      "`: failed to parse environment entry at line \{line}, column \{column}"
    HostDenied(_) => "environment source access denied"
    HostUnavailable(_) => "environment source access unavailable"
    SourceAccess => "failed to access environment source"
    InvalidPath => "dotenv path is invalid"
    Required => "dotenv file not found"
    ArgumentsRequireLists =>
      "multiple `--dotenv-filename` or `--dotenv-path` arguments require `set lists`"
    CommandUnavailable(index~) =>
      "dotenv command \{index} could not be executed"
    CommandFailed(index~, exit_code~) =>
      "dotenv command \{index} failed with exit code \{exit_code}"
  }
}

///|
fn redacted_host_error(error : @host.HostError) -> DotenvError {
  match error {
    CapabilityDenied(capability) => HostDenied(capability)
    CapabilityUnavailable(capability) => HostUnavailable(capability)
    NotFound(_) => Required
    _ => SourceAccess
  }
}

///|
pub fn DotenvError::exit_code(self : DotenvError) -> Int {
  match self {
    CommandFailed(exit_code~, ..) => exit_code
    _ => 1
  }
}
