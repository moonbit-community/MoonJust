///|
/// Dotenv failures never retain a source line or parsed value. This keeps both
/// rendered and structural diagnostics safe for secret-bearing input.
pub(all) suberror DotenvError {
  InvalidUtf8(path~ : @path.PathValue)
  Parse(line~ : Int32, column~ : Int32)
  ParseValue(line~ : Int32, column~ : Int32, value~ : String, index~ : Int32)
  ParseFile(path~ : @path.PathValue, line~ : Int32, column~ : Int32)
  ParseFileValue(
    path~ : @path.PathValue,
    line~ : Int32,
    column~ : Int32,
    value~ : String,
    index~ : Int32
  )
  HostDenied(@host.HostCapability)
  HostUnavailable(@host.HostCapability)
  SourceAccess
  InvalidPath
  Required
  ArgumentsRequireLists
  CommandUnavailable(index~ : Int32)
  CommandFailed(index~ : Int32, exit_code~ : Int32)
} derive(Eq, Debug)

///|
pub fn DotenvError::message(self : DotenvError) -> String {
  match self {
    InvalidUtf8(path~) =>
      "failed to load environment file from `\{path.as_string()}`: input is not valid UTF-8"
    Parse(line~, column~) =>
      "failed to parse environment entry at line \{line}, column \{column}"
    ParseValue(value~, index~, ..) =>
      "Error parsing line: '\{value}', error at line index: \{index}"
    ParseFile(path~, line~, column~) =>
      "failed to load environment file from `" +
      path.as_string() +
      "`: failed to parse environment entry at line \{line}, column \{column}"
    ParseFileValue(path~, value~, index~, ..) =>
      "failed to load environment file from `" +
      path.as_string() +
      "`: Error parsing line: '" +
      value +
      "', error at line index: " +
      index.to_string()
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
pub fn DotenvError::exit_code(self : DotenvError) -> Int32 {
  match self {
    CommandFailed(exit_code~, ..) => exit_code
    _ => 1
  }
}
