///|
/// How a command obtains its justfile input.
#derive(Eq, Debug)
pub(all) enum InputSelection {
  Search
  Stdin
  File(@path.PathValue)
}

///|
/// Query operations that do not execute recipes.
#derive(Eq, Debug)
pub(all) enum QueryKind {
  List
  Show(String)
  Summary
  Variables
  Dump
  Json
}

///|
/// Parsed application intent, independent of terminal and process adapters.
#derive(Eq, Debug)
pub(all) enum ApplicationRequest {
  Version
  Help
  Check(InputSelection)
  Format(InputSelection, check_only~ : Bool)
  Query(InputSelection, QueryKind)
  Run(InputSelection, ReadOnlyArray[String])
}

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
