///|
/// Failures raised while constructing or rendering diagnostics.
pub(all) suberror DiagnosticError {
  AnsiEscapeInField(field~ : String)
  MissingSource(@source.SourceId)
  InvalidLabelSpan(
    source_id~ : @source.SourceId,
    start_byte~ : Int,
    end_byte~ : Int
  )
} derive(Eq, Debug)

///|
fn reject_ansi(value : String, field : String) -> Unit raise DiagnosticError {
  if value.contains("\u{001b}") {
    raise AnsiEscapeInField(field~)
  }
}
