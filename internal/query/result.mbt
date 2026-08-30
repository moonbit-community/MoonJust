///|
/// Rendered read-only result returned to application without exposing query
/// implementation details.
pub struct QueryResult {
  stdout : Bytes
  stderr : Bytes
}

///|
pub fn QueryResult::new(
  stdout? : Bytes = b"",
  stderr? : Bytes = b"",
) -> QueryResult {
  { stdout, stderr, }
}

///|
pub fn QueryResult::stdout(self : QueryResult) -> BytesView {
  self.stdout[:]
}

///|
pub fn QueryResult::stderr(self : QueryResult) -> BytesView {
  self.stderr[:]
}
