///|
/// Machine-readable diagnostic importance.
pub(all) enum Severity {
  Error
  Warning
  Info
} derive(Eq, Debug)

///|
pub fn Severity::as_string(self : Severity) -> String {
  match self {
    Error => "error"
    Warning => "warning"
    Info => "info"
  }
}

///|
/// The visual role of a source label.
pub(all) enum LabelStyle {
  Primary
  Secondary
} derive(Eq, Debug)

///|
/// A message attached to a validated UTF-8 byte span.
pub struct DiagnosticLabel {
  span : @source.Span
  message : String
  style : LabelStyle
} derive(Eq, Debug)

///|
pub fn DiagnosticLabel::new(
  span : @source.Span,
  message : String,
  style : LabelStyle,
) -> DiagnosticLabel raise DiagnosticError {
  reject_ansi(message, "label.message")
  { span, message, style }
}

///|
pub fn DiagnosticLabel::span(self : DiagnosticLabel) -> @source.Span {
  self.span
}

///|
pub fn DiagnosticLabel::message(self : DiagnosticLabel) -> String {
  self.message
}

///|
pub fn DiagnosticLabel::style(self : DiagnosticLabel) -> LabelStyle {
  self.style
}

///|
/// One contextual step in a cross-source diagnostic chain.
pub struct SourceTrace {
  source_id : @source.SourceId
  message : String
} derive(Eq, Debug)

///|
pub fn SourceTrace::new(
  source_id : @source.SourceId,
  message : String,
) -> SourceTrace raise DiagnosticError {
  reject_ansi(message, "source_trace.message")
  { source_id, message }
}

///|
pub fn SourceTrace::source_id(self : SourceTrace) -> @source.SourceId {
  self.source_id
}

///|
pub fn SourceTrace::message(self : SourceTrace) -> String {
  self.message
}

///|
/// Structured diagnostic data independent of presentation and terminal state.
pub struct Diagnostic {
  code : String
  severity : Severity
  message : String
  primary : DiagnosticLabel
  secondary : Array[DiagnosticLabel]
  notes : Array[String]
  mut help : String?
  source_chain : Array[SourceTrace]
} derive(Debug)

///|
pub fn Diagnostic::new(
  code : String,
  severity : Severity,
  message : String,
  primary_span : @source.Span,
  primary_message : String,
) -> Diagnostic raise DiagnosticError {
  reject_ansi(code, "diagnostic.code")
  reject_ansi(message, "diagnostic.message")
  let primary = DiagnosticLabel::new(primary_span, primary_message, Primary)
  {
    code,
    severity,
    message,
    primary,
    secondary: [],
    notes: [],
    help: None,
    source_chain: [],
  }
}

///|
pub fn Diagnostic::code(self : Diagnostic) -> String {
  self.code
}

///|
pub fn Diagnostic::severity(self : Diagnostic) -> Severity {
  self.severity
}

///|
pub fn Diagnostic::message(self : Diagnostic) -> String {
  self.message
}

///|
pub fn Diagnostic::primary(self : Diagnostic) -> DiagnosticLabel {
  self.primary
}

///|
pub fn Diagnostic::secondary(self : Diagnostic) -> ArrayView[DiagnosticLabel] {
  self.secondary[:]
}

///|
pub fn Diagnostic::notes(self : Diagnostic) -> ArrayView[String] {
  self.notes[:]
}

///|
pub fn Diagnostic::help(self : Diagnostic) -> String? {
  self.help
}

///|
pub fn Diagnostic::source_chain(self : Diagnostic) -> ArrayView[SourceTrace] {
  self.source_chain[:]
}

///|
pub fn Diagnostic::add_secondary(
  self : Diagnostic,
  span : @source.Span,
  message : String,
) -> Unit raise DiagnosticError {
  self.secondary.push(DiagnosticLabel::new(span, message, Secondary))
}

///|
pub fn Diagnostic::add_note(
  self : Diagnostic,
  note : String,
) -> Unit raise DiagnosticError {
  reject_ansi(note, "diagnostic.note")
  self.notes.push(note)
}

///|
pub fn Diagnostic::set_help(
  self : Diagnostic,
  help : String,
) -> Unit raise DiagnosticError {
  reject_ansi(help, "diagnostic.help")
  self.help = Some(help)
}

///|
pub fn Diagnostic::add_source_trace(
  self : Diagnostic,
  source_id : @source.SourceId,
  message : String,
) -> Unit raise DiagnosticError {
  self.source_chain.push(SourceTrace::new(source_id, message))
}
