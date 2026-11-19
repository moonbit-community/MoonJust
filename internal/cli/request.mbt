///|
/// How a command obtains its justfile input.
#derive(Eq, Debug)
pub(all) enum InputSelection {
  Search
  Stdin
  File(@path.PathValue)
}
