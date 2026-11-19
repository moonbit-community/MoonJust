///|
/// Immutable facts selected before loading a project. The project package owns
/// these facts because every downstream phase consumes the same input snapshot.
#derive(Debug)
pub struct ProjectInput {
  cwd : @path.PathValue
  invocation_directory : @path.PathValue
  stdin : Bytes
  source_id : @source.SourceId
  global_justfile : @path.PathValue?
  global_project_directory : @path.PathValue?
}

///|
pub fn ProjectInput::new(
  cwd : @path.PathValue,
  stdin~ : Bytes = b"",
  source_id~ : @source.SourceId = @source.SourceId::new(1),
) -> ProjectInput {
  {
    cwd,
    invocation_directory: cwd,
    stdin,
    source_id,
    global_justfile: None,
    global_project_directory: None,
  }
}

///|
pub fn ProjectInput::with_global_justfile(
  self : ProjectInput,
  justfile : @path.PathValue,
  project_directory : @path.PathValue,
) -> ProjectInput {
  {
    ..self,
    global_justfile: Some(justfile),
    global_project_directory: Some(project_directory),
  }
}

///|
pub fn ProjectInput::with_cwd(
  self : ProjectInput,
  cwd : @path.PathValue,
) -> ProjectInput {
  { ..self, cwd, }
}

///|
pub fn ProjectInput::invocation_directory(
  self : ProjectInput,
) -> @path.PathValue {
  self.invocation_directory
}

///|
pub fn ProjectInput::cwd(self : ProjectInput) -> @path.PathValue {
  self.cwd
}

///|
pub fn ProjectInput::stdin(self : ProjectInput) -> BytesView {
  self.stdin[:]
}

///|
pub fn ProjectInput::source_id(self : ProjectInput) -> @source.SourceId {
  self.source_id
}

///|
pub fn ProjectInput::global_justfile(self : ProjectInput) -> @path.PathValue? {
  self.global_justfile
}

///|
pub fn ProjectInput::global_project_directory(
  self : ProjectInput,
) -> @path.PathValue? {
  self.global_project_directory
}
