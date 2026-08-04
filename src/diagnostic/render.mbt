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
  let line_end_column = if start.line() == end.line() {
    end.scalar_column()
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
    line_end.scalar_column()
  }
  let width = Int::max(1, line_end_column - start.scalar_column())
  builder.write_string(
    " --> \{source.name()}:\{start.line()}:\{start.scalar_column() + 1}\n",
  )
  builder.write_string("  |\n")
  builder.write_string("\{start.line()} | \{line_text}\n")
  builder.write_string("  | ")
  write_repeated(builder, ' ', start.scalar_column())
  write_repeated(builder, marker, width)
  builder.write_string(" \{label.message()}")
  if end.line() != start.line() {
    builder.write_string(" (continues to line \{end.line()})")
  }
  builder.write_char('\n')
}

///|
/// Render a deterministic, color-free diagnostic for snapshots and plain text.
pub fn render_text(
  diagnostic : Diagnostic,
  sources : @source.SourceMap,
) -> String raise DiagnosticError {
  let builder = StringBuilder()
  builder.write_string(
    "\{diagnostic.severity().as_string()}[\{diagnostic.code()}]: \{diagnostic.message()}\n",
  )
  render_label(builder, sources, diagnostic.primary())
  for label in diagnostic.secondary() {
    render_label(builder, sources, label)
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
