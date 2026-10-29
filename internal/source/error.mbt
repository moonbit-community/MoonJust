///|
/// Errors produced while constructing or indexing source text.
pub(all) suberror SourceError {
  InvalidUtf8(offset~ : Int32)
  InvalidSpan(start_byte~ : Int32, end_byte~ : Int32)
  WrongSource(expected~ : SourceId, actual~ : SourceId)
  OffsetOutOfBounds(offset~ : Int32, length~ : Int32)
  InvalidUtf8Boundary(offset~ : Int32)
  InvalidLine(line~ : Int32, line_count~ : Int32)
  DisjointSpans(
    first_start~ : Int32,
    first_end~ : Int32,
    second_start~ : Int32,
    second_end~ : Int32
  )
  DuplicateSource(SourceId)
  MissingSource(SourceId)
} derive(Eq, Debug)
