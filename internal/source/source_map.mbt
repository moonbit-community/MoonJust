///|
/// In-memory lookup of loaded sources by stable identity.
pub struct SourceMap {
  sources : Map[SourceId, Source]
}

///|
/// Create an empty source map.
pub fn SourceMap::new() -> SourceMap {
  { sources: {}, }
}

///|
/// Return the number of registered sources.
pub fn SourceMap::length(self : SourceMap) -> Int {
  self.sources.length()
}

///|
/// Add a source, rejecting duplicate identities.
pub fn SourceMap::add(
  self : SourceMap,
  source : Source,
) -> Unit raise SourceError {
  if self.sources.contains(source.id()) {
    raise DuplicateSource(source.id())
  }
  self.sources[source.id()] = source
}

///|
/// Look up a source without raising.
pub fn SourceMap::get(self : SourceMap, id : SourceId) -> Source? {
  self.sources.get(id)
}

///|
/// Look up a source or return a typed missing-source error.
pub fn SourceMap::require(
  self : SourceMap,
  id : SourceId,
) -> Source raise SourceError {
  match self.sources.get(id) {
    Some(source) => source
    None => raise MissingSource(id)
  }
}
