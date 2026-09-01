///|
fn write_repeated(
  builder : StringBuilder,
  character : Char,
  count : Int,
) -> Unit {
  let mut remaining = count
  while remaining > 0 {
    builder.write_char(character)
    remaining -= 1
  }
}

///|
fn expanded_source_line(line : String) -> String {
  let builder = StringBuilder()
  for character in line {
    if character == '\t' {
      builder.write_string("    ")
    } else {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
fn source_character_width(character : Char) -> Int {
  let code = character.to_int()
  if (code >= 0x0300 && code <= 0x036F) ||
    (code >= 0x1AB0 && code <= 0x1AFF) ||
    (code >= 0x1DC0 && code <= 0x1DFF) ||
    (code >= 0x20D0 && code <= 0x20FF) ||
    (code >= 0xFE00 && code <= 0xFE0F) ||
    (code >= 0xFE20 && code <= 0xFE2F) {
    0
  } else if (code >= 0x1100 && code <= 0x115F) ||
    code == 0x2329 ||
    code == 0x232A ||
    (code >= 0x2E80 && code <= 0xA4CF && code != 0x303F) ||
    (code >= 0xAC00 && code <= 0xD7A3) ||
    (code >= 0xF900 && code <= 0xFAFF) ||
    (code >= 0xFE10 && code <= 0xFE19) ||
    (code >= 0xFE30 && code <= 0xFE6F) ||
    (code >= 0xFF00 && code <= 0xFF60) ||
    (code >= 0xFFE0 && code <= 0xFFE6) ||
    (code >= 0x1F300 && code <= 0x1FAFF) ||
    (code >= 0x20000 && code <= 0x3FFFD) {
    2
  } else {
    1
  }
}

///|
fn visual_source_column(line : String, scalar_column : Int) -> Int {
  let mut visual = 0
  let mut scalar = 0
  for character in line {
    if scalar >= scalar_column {
      break
    }
    visual += if character == '\t' {
      4
    } else {
      source_character_width(character)
    }
    scalar += 1
  }
  visual
}

///|
fn require_source(
  sources : @source.SourceMap,
  id : @source.SourceId,
) -> @source.Source raise DiagnosticError {
  match sources.get(id) {
    Some(source) => source
    None => raise MissingSource(id)
  }
}

///|
fn locate_label(
  source : @source.Source,
  span : @source.Span,
) -> (@source.SourcePosition, @source.SourcePosition) raise DiagnosticError {
  if span.is_empty() && span.start_byte() == source.length() {
    let position = source.locate_terminal_eof() catch {
      _ =>
        raise InvalidLabelSpan(
          source_id=span.source_id(),
          start_byte=span.start_byte(),
          end_byte=span.end_byte(),
        )
    }
    return (position, position)
  }
  (source.locate(span.start_byte()), source.locate(span.end_byte())) catch {
    _ =>
      raise InvalidLabelSpan(
        source_id=span.source_id(),
        start_byte=span.start_byte(),
        end_byte=span.end_byte(),
      )
  }
}

///|
fn render_label(
  builder : StringBuilder,
  sources : @source.SourceMap,
  label : DiagnosticLabel,
  color : Bool,
) -> Unit raise DiagnosticError {
  let span = label.span()
  let source = require_source(sources, span.source_id())
  let (start, end) = locate_label(source, span)
  let line_text = source.line_text(start.line()) catch {
    _ =>
      raise InvalidLabelSpan(
        source_id=span.source_id(),
        start_byte=span.start_byte(),
        end_byte=span.end_byte(),
      )
  }
  let marker = match label.style() {
    Primary => '^'
    Secondary => '-'
  }
  let start_visual_column = visual_source_column(
    line_text,
    start.scalar_column(),
  )
  let line_end_column = if start.line() == end.line() {
    visual_source_column(line_text, end.scalar_column())
  } else {
    let line_span = source.line_span(start.line()) catch {
      _ =>
        raise InvalidLabelSpan(
          source_id=span.source_id(),
          start_byte=span.start_byte(),
          end_byte=span.end_byte(),
        )
    }
    let line_end = source.locate(line_span.end_byte()) catch {
      _ =>
        raise InvalidLabelSpan(
          source_id=span.source_id(),
          start_byte=span.start_byte(),
          end_byte=span.end_byte(),
        )
    }
    visual_source_column(line_text, line_end.scalar_column())
  }
  let width = Int::max(1, line_end_column - start_visual_column)
  let gutter_width = start.line().to_string().length()
  write_repeated(builder, ' ', gutter_width)
  if color {
    builder.write_string("\u{001b}[1;34m——▶\u{001b}[0m")
  } else {
    builder.write_string("——▶")
  }
  builder.write_string(
    " \{source.name()}:\{start.line()}:\{start.byte_column() + 1}\n",
  )
  write_repeated(builder, ' ', gutter_width + 1)
  builder.write_string(
    if color {
      "\u{001b}[1;34m│\u{001b}[0m\n"
    } else {
      "│\n"
    },
  )
  if color {
    builder.write_string("\u{001b}[1;34m\{start.line()} │\u{001b}[0m ")
  } else {
    builder.write_string("\{start.line()} │ ")
  }
  builder.write_string(expanded_source_line(line_text) + "\n")
  write_repeated(builder, ' ', gutter_width + 1)
  builder.write_string(
    if color {
      "\u{001b}[1;34m│\u{001b}[0m "
    } else {
      "│ "
    },
  )
  write_repeated(builder, ' ', start_visual_column)
  if color {
    builder.write_string(
      if label.style() is Primary {
        "\u{001b}[1;31m"
      } else {
        "\u{001b}[1;34m"
      },
    )
  }
  write_repeated(builder, marker, width)
  if color {
    builder.write_string("\u{001b}[0m")
  }
  if label.message() != "" {
    builder.write_string(" \{label.message()}")
  }
  if end.line() != start.line() {
    builder.write_string(" (continues to line \{end.line()})")
  }
  builder.write_char('\n')
}

///|
fn quoted_name(message : String) -> String {
  let mut index = 0
  for part in message.split("`") {
    if index == 1 {
      return part.to_owned()
    }
    index += 1
  }
  ""
}

///|
fn quoted_values(message : String) -> Array[String] {
  let values : Array[String] = []
  let mut index = 0
  for part in message.split("`") {
    if index % 2 == 1 {
      values.push(part.to_owned())
    }
    index += 1
  }
  values
}

///|
fn contextual_message(
  diagnostic : Diagnostic,
  sources : @source.SourceMap,
) -> String raise DiagnosticError {
  guard diagnostic.related().get(0) is Some(first) else {
    return diagnostic.message()
  }
  let first_source = require_source(sources, first.source_id())
  let first_line = locate_label(first_source, first).0.line()
  let primary = diagnostic.primary().span()
  let primary_source = require_source(sources, primary.source_id())
  let second_line = locate_label(primary_source, primary).0.line()
  let name = quoted_name(diagnostic.message())
  match diagnostic.code() {
    "MJ-SEM-0001" =>
      "recipe `" +
      name +
      "` first defined on line " +
      first_line.to_string() +
      " is redefined on line " +
      second_line.to_string()
    "MJ-SEM-0014" =>
      "function `" +
      name +
      "` first defined on line " +
      first_line.to_string() +
      " is redefined on line " +
      second_line.to_string()
    "MJ-SEM-0030" => {
      let parts : Array[String] = []
      for part in diagnostic.message().split(" is redefined as a ") {
        parts.push(part.to_owned())
      }
      if parts.length() != 2 {
        return diagnostic.message()
      }
      let subject = parts[0]
      let second_kind = parts[1]
      let repeated = subject.has_prefix(second_kind + " ")
      if repeated {
        subject +
        " first defined on line " +
        first_line.to_string() +
        " is redefined on line " +
        second_line.to_string()
      } else {
        subject +
        " defined on line " +
        first_line.to_string() +
        " is redefined as " +
        (if second_kind == "alias" { "an " } else { "a " }) +
        second_kind +
        " on line " +
        second_line.to_string()
      }
    }
    "MJ-SEM-0009" => {
      let values = quoted_values(diagnostic.message())
      if values.length() != 2 {
        return diagnostic.message()
      }
      "`" +
      values[0] +
      "` set on line " +
      first_line.to_string() +
      " is incompatible with `" +
      values[1] +
      "`"
    }
    "MJ-SEM-0037" =>
      "attribute `" +
      name +
      "` first used on line " +
      first_line.to_string() +
      " is duplicated on line " +
      second_line.to_string()
    "MJ-SEM-0038" =>
      "`[group('" +
      name +
      "')]` attribute first used on line " +
      first_line.to_string() +
      " is duplicated on line " +
      second_line.to_string()
    "MJ-INV-0020" =>
      "attribute for argument `" +
      name +
      "` first used on line " +
      first_line.to_string() +
      " is duplicated on line " +
      second_line.to_string()
    _ => diagnostic.message()
  }
}

///|
/// Render a deterministic, color-free diagnostic for snapshots and plain text.
fn render(
  diagnostic : Diagnostic,
  sources : @source.SourceMap,
  color : Bool,
) -> String raise DiagnosticError {
  let builder = StringBuilder()
  if color {
    let severity_color = match diagnostic.severity() {
      Error => "31"
      Warning => "33"
      Info => "34"
    }
    builder.write_string(
      "\u{001b}[1;" +
      severity_color +
      "m" +
      diagnostic.severity().as_string() +
      "\u{001b}[0m: \u{001b}[1m" +
      contextual_message(diagnostic, sources) +
      "\u{001b}[0m\n",
    )
  } else {
    builder.write_string(
      "\{diagnostic.severity().as_string()}: \{contextual_message(diagnostic, sources)}\n",
    )
  }
  render_label(builder, sources, diagnostic.primary(), color)
  for label in diagnostic.secondary() {
    render_label(builder, sources, label, color)
  }
  for trailer in diagnostic.trailers() {
    builder.write_string(trailer)
    if !trailer.has_suffix("\n") {
      builder.write_char('\n')
    }
  }
  for trace in diagnostic.source_chain() {
    let source = require_source(sources, trace.source_id())
    builder.write_string("  = source: \{trace.message()} (\{source.name()})\n")
  }
  for note in diagnostic.notes() {
    builder.write_string("  = note: \{note}\n")
  }
  match diagnostic.help() {
    Some(help) => builder.write_string("  = help: \{help}\n")
    None => ()
  }
  builder.to_string()
}

///|
/// Render a deterministic, color-free diagnostic for snapshots and plain text.
pub fn render_text(
  diagnostic : Diagnostic,
  sources : @source.SourceMap,
) -> String raise DiagnosticError {
  render(diagnostic, sources, false)
}

///|
/// Render the same diagnostic structure with the ANSI styles used by just.
pub fn render_colored_text(
  diagnostic : Diagnostic,
  sources : @source.SourceMap,
) -> String raise DiagnosticError {
  render(diagnostic, sources, true)
}
