///|
/// Explicit invocation data used by the query application.
pub struct ApplicationContext {
  cwd : @path.PathValue
  stdin : Bytes
  source_id : @source.SourceId
  global_justfile : @path.PathValue?
  global_project_directory : @path.PathValue?
} derive(Debug)

///|
pub fn ApplicationContext::new(
  cwd : @path.PathValue,
  stdin? : Bytes = b"",
  source_id? : @source.SourceId = @source.SourceId::new(1),
) -> ApplicationContext {
  {
    cwd,
    stdin,
    source_id,
    global_justfile: None,
    global_project_directory: None,
  }
}

///|
pub fn ApplicationContext::with_global_justfile(
  self : ApplicationContext,
  justfile : @path.PathValue,
  project_directory : @path.PathValue,
) -> ApplicationContext {
  {
    cwd: self.cwd,
    stdin: self.stdin,
    source_id: self.source_id,
    global_justfile: Some(justfile),
    global_project_directory: Some(project_directory),
  }
}

///|
pub fn ApplicationContext::with_cwd(
  self : ApplicationContext,
  cwd : @path.PathValue,
) -> ApplicationContext {
  {
    cwd,
    stdin: self.stdin,
    source_id: self.source_id,
    global_justfile: self.global_justfile,
    global_project_directory: self.global_project_directory,
  }
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

///|
pub fn ApplicationContext::global_justfile(
  self : ApplicationContext,
) -> @path.PathValue? {
  self.global_justfile
}

///|
pub fn ApplicationContext::global_project_directory(
  self : ApplicationContext,
) -> @path.PathValue? {
  self.global_project_directory
}
