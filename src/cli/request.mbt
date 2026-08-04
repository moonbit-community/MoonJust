///|
/// How a command obtains its justfile input.
pub(all) enum InputSelection {
  Search
  Stdin
  File(@path.PathValue)
} derive(Eq, Debug)

///|
/// Query operations that do not execute recipes.
pub(all) enum QueryKind {
  List
  Show(String)
  Summary
  Variables
  Dump
  Json
} derive(Eq, Debug)

///|
/// Parsed application intent, independent of terminal and process adapters.
pub(all) enum ApplicationRequest {
  Version
  Help
  Check(InputSelection)
  Format(InputSelection, check_only~ : Bool)
  Query(InputSelection, QueryKind)
  Run(InputSelection, ReadOnlyArray[String])
} derive(Eq, Debug)

///|
/// Build a run request while taking an immutable snapshot of recipe arguments.
pub fn ApplicationRequest::run(
  input : InputSelection,
  arguments : Array[String],
) -> ApplicationRequest {
  Run(input, ReadOnlyArray::from_array(arguments[:]))
}

///|
pub fn ApplicationRequest::arguments(
  self : ApplicationRequest,
) -> ReadOnlyArray[String]? {
  match self {
    Run(_, arguments) => Some(arguments)
    _ => None
  }
}
