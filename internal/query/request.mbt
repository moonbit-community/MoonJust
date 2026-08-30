///|
/// Immutable query input. Query owns interpretation of read-only command
/// options; application owns only host preparation and response routing.
pub struct QueryRequest {
  arguments : @cli.CliArguments
}

///|
pub fn build_query(arguments : @cli.CliArguments) -> QueryRequest {
  { arguments, }
}

///|
pub fn QueryRequest::arguments(self : QueryRequest) -> @cli.CliArguments {
  self.arguments
}
