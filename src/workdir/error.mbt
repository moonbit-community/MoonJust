///|
/// Failures while composing explicit working-directory state.
pub(all) suberror WorkingDirectoryError {
  Path(@path.PathError)
  JustfileWithoutParent(@path.PathValue)
} derive(Eq, Debug)

///|
pub fn WorkingDirectoryError::code(self : WorkingDirectoryError) -> String {
  match self {
    Path(_) => "MJ-CWD-0001"
    JustfileWithoutParent(_) => "MJ-CWD-0002"
  }
}

///|
pub fn WorkingDirectoryError::message(self : WorkingDirectoryError) -> String {
  match self {
    Path(_) => "working-directory path composition failed"
    JustfileWithoutParent(path) =>
      "justfile path had no parent: " + path.as_string()
  }
}
