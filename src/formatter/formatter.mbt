///|
/// Format a parsed syntax tree using stable whitespace and line endings.
pub fn format(ast : @syntax.Ast) -> String {
  format_unchecked(ast, "    ")
}

///|
fn format_unchecked(ast : @syntax.Ast, indentation : String) -> String {
  let builder = StringBuilder()
  let mut previous_blank = false
  let items = ast.items()
  let mut index = 0
  while index < items.length() {
    let item = items[index]
    if item is TrailingComment(_) {
      index += 1
      continue
    }
    let blank = item is Blank(_)
    if blank && previous_blank {
      index += 1
      continue
    }
    match item {
      Comment(text~, ..) if index > 0 && text.has_prefix("#!") => {
        builder.write_string("# ")
        builder.write_string(text.view(start_offset=1).to_owned())
      }
      _ => builder.write_string(item_text(item, indentation))
    }
    if items.get(index + 1) is Some(TrailingComment(text~, ..)) {
      builder.write_char(' ')
      builder.write_string(text)
      index += 1
    }
    builder.write_char('\n')
    previous_blank = blank
    index += 1
  }
  builder.to_string()
}

///|
fn validate_indentation(indentation : String) -> Unit raise FormatterError {
  if indentation.is_empty() {
    raise InvalidInput("indentation must not be empty")
  }
  let mut spaces = false
  let mut tabs = false
  for character in indentation {
    match character {
      ' ' => spaces = true
      '\t' => tabs = true
      _ => raise InvalidInput("indentation must be spaces or tabs")
    }
  }
  if spaces && tabs {
    raise InvalidInput("indentation may not be mixed")
  }
}

///|
pub fn format_with_indentation(
  ast : @syntax.Ast,
  indentation : String,
) -> String raise FormatterError {
  validate_indentation(indentation)
  format_unchecked(ast, indentation)
}

///|
/// Parse and format source text.
pub fn format_source(source : @source.Source) -> String raise FormatterError {
  let ast = @parser.parse(source) catch { error => raise Parse(error) }
  format(ast)
}

///|
pub fn format_source_with_indentation(
  source : @source.Source,
  indentation : String,
) -> String raise FormatterError {
  let ast = @parser.parse(source) catch { error => raise Parse(error) }
  format_with_indentation(ast, indentation)
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
pub fn check_with_indentation(
  source : @source.Source,
  indentation : String,
) -> CheckResult raise FormatterError {
  let formatted = format_source_with_indentation(source, indentation)
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
