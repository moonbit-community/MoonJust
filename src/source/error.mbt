///|
/// Errors produced while constructing or indexing source text.
pub(all) suberror SourceError {
  InvalidUtf8(offset~ : Int)
  InvalidSpan(start_byte~ : Int, end_byte~ : Int)
  WrongSource(expected~ : SourceId, actual~ : SourceId)
  OffsetOutOfBounds(offset~ : Int, length~ : Int)
  InvalidUtf8Boundary(offset~ : Int)
  InvalidLine(line~ : Int, line_count~ : Int)
  DisjointSpans(
    first_start~ : Int,
    first_end~ : Int,
    second_start~ : Int,
    second_end~ : Int
  )
  DuplicateSource(SourceId)
  MissingSource(SourceId)
} derive(Eq, Debug)
