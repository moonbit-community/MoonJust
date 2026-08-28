///|
/// Human-facing position resolved from a UTF-8 byte offset.
pub struct SourcePosition {
  line : Int
  byte_column : Int
  scalar_column : Int
} derive(Eq, Debug)

///|
/// Return the one-based line number.
pub fn SourcePosition::line(self : SourcePosition) -> Int {
  self.line
}

///|
/// Return the zero-based UTF-8 byte column.
pub fn SourcePosition::byte_column(self : SourcePosition) -> Int {
  self.byte_column
}

///|
/// Return the zero-based Unicode scalar column.
pub fn SourcePosition::scalar_column(self : SourcePosition) -> Int {
  self.scalar_column
}

///|
/// Validated UTF-8 source text and its byte-based line index.
pub struct Source {
  id : SourceId
  name : String
  bytes : Bytes
  line_starts : Array[Int]
} derive(Debug)

///|
fn build_line_index(bytes : Bytes) -> Array[Int] {
  let starts = [0]
  for index, byte in bytes {
    if byte == b'\n' {
      starts.push(index + 1)
    }
  }
  starts
}

///|
/// Construct a source after validating all bytes as UTF-8.
pub fn Source::from_bytes(
  id : SourceId,
  name : String,
  bytes : Bytes,
) -> Source raise SourceError {
  (@utf8.decode(bytes) |> ignore) catch {
    Malformed(fragment) =>
      raise InvalidUtf8(offset=bytes.length() - fragment.length())
  }
  { id, name, bytes, line_starts: build_line_index(bytes), }
}

///|
/// Construct a source from a MoonBit string.
pub fn Source::from_text(id : SourceId, name : String, text : String) -> Source {
  let bytes = @utf8.encode(text)
  { id, name, bytes, line_starts: build_line_index(bytes), }
}

///|
/// Return this source's stable identity.
pub fn Source::id(self : Source) -> SourceId {
  self.id
}

///|
/// Return the display name supplied by the loader.
pub fn Source::name(self : Source) -> String {
  self.name
}

///|
/// Borrow the validated UTF-8 bytes.
pub fn Source::bytes(self : Source) -> BytesView {
  self.bytes[:]
}

///|
/// Decode and return the complete source text.
pub fn Source::text(self : Source) -> String {
  try! @utf8.decode(self.bytes)
}

///|
/// Return the source length in UTF-8 bytes.
pub fn Source::length(self : Source) -> Int {
  self.bytes.length()
}

///|
/// Return the number of logical lines. Empty input has one line.
pub fn Source::line_count(self : Source) -> Int {
  self.line_starts.length()
}

///|
fn Source::check_offset(self : Source, offset : Int) -> Unit raise SourceError {
  if offset < 0 || offset > self.bytes.length() {
    raise OffsetOutOfBounds(offset~, length=self.bytes.length())
  }
}

///|
/// A validated UTF-8 source can reject an interior byte boundary by looking
/// only at the byte immediately following the boundary. Continuation bytes
/// are never valid starts of a scalar, so this keeps boundary checks O(1).
fn is_utf8_continuation(byte : Byte) -> Bool {
  byte >= 0x80 && byte <= 0xBF
}

///|
fn Source::check_boundary(
  self : Source,
  offset : Int,
) -> Unit raise SourceError {
  self.check_offset(offset)
  if offset < self.bytes.length() && is_utf8_continuation(self.bytes[offset]) {
    raise InvalidUtf8Boundary(offset~)
  }
}

///|
fn Source::line_index_for_offset(
  self : Source,
  offset : Int,
) -> Int raise SourceError {
  self.check_offset(offset)
  match self.line_starts.binary_search(offset) {
    Ok(index) => index
    Err(insertion) => insertion - 1
  }
}

///|
fn Source::check_line(self : Source, line : Int) -> Int raise SourceError {
  if line < 1 || line > self.line_starts.length() {
    raise InvalidLine(line~, line_count=self.line_starts.length())
  }
  line - 1
}

///|
/// Return the byte offset at the start of a one-based line.
pub fn Source::line_start(self : Source, line : Int) -> Int raise SourceError {
  let index = self.check_line(line)
  self.line_starts[index]
}

///|
/// Return a line span without its LF or CRLF terminator.
pub fn Source::line_span(self : Source, line : Int) -> Span raise SourceError {
  let index = self.check_line(line)
  let start_byte = self.line_starts[index]
  let raw_end = if index + 1 < self.line_starts.length() {
    self.line_starts[index + 1]
  } else {
    self.bytes.length()
  }
  let without_lf = if raw_end > start_byte && self.bytes[raw_end - 1] == b'\n' {
    raw_end - 1
  } else {
    raw_end
  }
  let end_byte = if without_lf > start_byte &&
    self.bytes[without_lf - 1] == b'\r' {
    without_lf - 1
  } else {
    without_lf
  }
  { source_id: self.id, start_byte, end_byte, }
}

///|
/// Return one decoded line without its line terminator.
pub fn Source::line_text(self : Source, line : Int) -> String raise SourceError {
  self.slice_text(self.line_span(line))
}

///|
/// Resolve a UTF-8 boundary offset to line and column values.
pub fn Source::locate(
  self : Source,
  offset : Int,
) -> SourcePosition raise SourceError {
  self.check_boundary(offset)
  let line_index = self.line_index_for_offset(offset)
  let line_start = self.line_starts[line_index]
  let mut scalar_column = 0
  // The source was validated at construction, so every non-continuation
  // byte in the requested prefix starts exactly one Unicode scalar.
  for byte in self.bytes[line_start:offset] {
    if !is_utf8_continuation(byte) {
      scalar_column += 1
    }
  }
  { line: line_index + 1, byte_column: offset - line_start, scalar_column, }
}

///|
/// Locate an EOF label as the column after a terminal line ending. This keeps
/// parser diagnostics attached to the final non-empty source line.
pub fn Source::locate_terminal_eof(
  self : Source,
) -> SourcePosition raise SourceError {
  if self.bytes.is_empty() || self.bytes[self.bytes.length() - 1] != b'\n' {
    return self.locate(self.bytes.length())
  }
  let newline = self.locate(self.bytes.length() - 1)
  {
    line: newline.line,
    byte_column: newline.byte_column + 1,
    scalar_column: newline.scalar_column + 1,
  }
}

///|
fn Source::validate_span(self : Source, span : Span) -> Unit raise SourceError {
  if span.source_id() != self.id {
    raise WrongSource(expected=self.id, actual=span.source_id())
  }
  self.check_offset(span.start_byte())
  self.check_offset(span.end_byte())
}

///|
/// Borrow the bytes covered by a span.
pub fn Source::slice_bytes(
  self : Source,
  span : Span,
) -> BytesView raise SourceError {
  self.validate_span(span)
  self.bytes[span.start_byte():span.end_byte()]
}

///|
/// Decode the bytes covered by a span, rejecting split UTF-8 sequences.
pub fn Source::slice_text(
  self : Source,
  span : Span,
) -> String raise SourceError {
  self.validate_span(span)
  self.check_boundary(span.start_byte())
  self.check_boundary(span.end_byte())
  try! @utf8.decode(self.bytes[span.start_byte():span.end_byte()])
}

///|
/// Return a span covering the complete source.
pub fn Source::full_span(self : Source) -> Span {
  { source_id: self.id, start_byte: 0, end_byte: self.bytes.length(), }
}

///|
/// Return an empty span at end of file.
pub fn Source::eof_span(self : Source) -> Span {
  {
    source_id: self.id,
    start_byte: self.bytes.length(),
    end_byte: self.bytes.length(),
  }
}
