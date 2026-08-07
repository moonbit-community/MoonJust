///|
/// Explicit invocation data used by the query application.
pub struct ApplicationContext {
  cwd : @path.PathValue
  stdin : Bytes
  source_id : @source.SourceId
} derive(Debug)

///|
pub fn ApplicationContext::new(
  cwd : @path.PathValue,
  stdin? : Bytes = b"",
  source_id? : @source.SourceId = @source.SourceId::new(1),
) -> ApplicationContext {
  { cwd, stdin, source_id }
}

///|
pub fn ApplicationContext::cwd(self : ApplicationContext) -> @path.PathValue {
  self.cwd
}

///|
pub fn ApplicationContext::stdin(self : ApplicationContext) -> BytesView {
  self.stdin[:]
}

///|
pub fn ApplicationContext::source_id(
  self : ApplicationContext,
) -> @source.SourceId {
  self.source_id
}
