///|
/// Format a parsed syntax tree using stable whitespace and line endings.
pub fn format(ast : @syntax.Ast) -> String {
  let builder = StringBuilder()
  for item in ast.items() {
    builder.write_string(item_text(item))
    builder.write_char('\n')
  }
  builder.to_string()
}

///|
/// Parse and format source text.
pub fn format_source(source : @source.Source) -> String raise FormatterError {
  let ast = @parser.parse(source) catch { error => raise Parse(error) }
  format(ast)
}

///|
/// Return true when formatting would not change the source bytes.
pub fn is_formatted(source : @source.Source) -> Bool raise FormatterError {
  format_source(source) == source.text()
}

///|
/// Format-check result with the canonical replacement, suitable for CLI diff.
pub struct CheckResult {
  formatted : String
  changed : Bool
} derive(Eq, Debug)

///|
pub fn CheckResult::formatted(self : CheckResult) -> String {
  self.formatted
}

///|
pub fn CheckResult::changed(self : CheckResult) -> Bool {
  self.changed
}

///|
pub fn check(source : @source.Source) -> CheckResult raise FormatterError {
  let formatted = format_source(source)
  { formatted, changed: formatted != source.text() }
}

///|
pub fn diff(source : @source.Source) -> String raise FormatterError {
  let result = check(source)
  if !result.changed() {
    ""
  } else {
    "--- justfile\n+++ justfile (formatted)\n" + result.formatted()
  }
}
