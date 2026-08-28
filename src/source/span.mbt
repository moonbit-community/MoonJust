///|
/// Stable identity for one loaded source.
pub struct SourceId(Int) derive(Eq, Compare, Hash, Debug)

///|
/// Create a source identity from an application-assigned integer.
pub fn SourceId::new(value : Int) -> SourceId {
  SourceId(value)
}

///|
/// Return the application-assigned integer value.
pub fn SourceId::value(self : SourceId) -> Int {
  self.0
}

///|
/// A half-open UTF-8 byte range within one source.
pub struct Span {
  source_id : SourceId
  start_byte : Int
  end_byte : Int
} derive(Eq, Hash, Debug)

///|
/// Create a half-open byte span.
pub fn Span::new(
  source_id : SourceId,
  start_byte : Int,
  end_byte : Int,
) -> Span raise SourceError {
  if start_byte < 0 || end_byte < start_byte {
    raise InvalidSpan(start_byte~, end_byte~)
  }
  { source_id, start_byte, end_byte, }
}

///|
/// Create an empty span at the start of a source.
pub fn Span::origin(source_id : SourceId) -> Span {
  { source_id, start_byte: 0, end_byte: 0, }
}

///|
/// Return the source containing this span.
pub fn Span::source_id(self : Span) -> SourceId {
  self.source_id
}

///|
/// Return the inclusive start byte offset.
pub fn Span::start_byte(self : Span) -> Int {
  self.start_byte
}

///|
/// Return the exclusive end byte offset.
pub fn Span::end_byte(self : Span) -> Int {
  self.end_byte
}

///|
/// Return the span length in UTF-8 bytes.
pub fn Span::length(self : Span) -> Int {
  self.end_byte - self.start_byte
}

///|
/// Return whether this span is empty.
pub fn Span::is_empty(self : Span) -> Bool {
  self.start_byte == self.end_byte
}

///|
/// Return whether the byte offset is in this half-open span.
pub fn Span::contains(self : Span, offset : Int) -> Bool {
  self.start_byte <= offset && offset < self.end_byte
}

///|
/// Create an empty span at this span's exclusive end.
pub fn Span::at_end(self : Span) -> Span {
  { ..self, start_byte: self.end_byte, }
}

///|
/// Join two overlapping or adjacent spans from the same source.
pub fn Span::cover(self : Span, other : Span) -> Span raise SourceError {
  if self.source_id != other.source_id {
    raise WrongSource(expected=self.source_id, actual=other.source_id)
  }
  if other.start_byte > self.end_byte || self.start_byte > other.end_byte {
    raise DisjointSpans(
      first_start=self.start_byte,
      first_end=self.end_byte,
      second_start=other.start_byte,
      second_end=other.end_byte,
    )
  }
  {
    source_id: self.source_id,
    start_byte: Int::min(self.start_byte, other.start_byte),
    end_byte: Int::max(self.end_byte, other.end_byte),
  }
}
