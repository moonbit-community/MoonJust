///|
/// Project sources and working-directory facts resolved by one load operation.
/// Formatting and fast queries can consume this value without forcing semantic
/// compilation, while full project preparation builds a `ProjectSnapshot`.
pub struct ProjectSources {
  graph : @loader.LoadedGraph
  directories : @workdir.WorkingDirectoryModel
}

///|
pub fn ProjectSources::new(
  graph : @loader.LoadedGraph,
  directories : @workdir.WorkingDirectoryModel,
) -> ProjectSources {
  { graph, directories, }
}

///|
pub fn ProjectSources::graph(self : ProjectSources) -> @loader.LoadedGraph {
  self.graph
}

///|
pub fn ProjectSources::directories(
  self : ProjectSources,
) -> @workdir.WorkingDirectoryModel {
  self.directories
}

///|
/// The immutable result of project discovery, loading, and semantic
/// compilation. Query and planning consume this value instead of rebuilding
/// parallel tuples with subtly different lifetimes.
pub struct ProjectSnapshot {
  graph : @loader.LoadedGraph
  compilation : @semantic.ProjectCompilation
  directories : @workdir.WorkingDirectoryModel
}

///|
pub fn ProjectSnapshot::new(
  graph : @loader.LoadedGraph,
  compilation : @semantic.ProjectCompilation,
  directories : @workdir.WorkingDirectoryModel,
) -> ProjectSnapshot {
  { graph, compilation, directories, }
}

///|
pub fn ProjectSnapshot::graph(self : ProjectSnapshot) -> @loader.LoadedGraph {
  self.graph
}

///|
pub fn ProjectSnapshot::compilation(
  self : ProjectSnapshot,
) -> @semantic.ProjectCompilation {
  self.compilation
}

///|
pub fn ProjectSnapshot::directories(
  self : ProjectSnapshot,
) -> @workdir.WorkingDirectoryModel {
  self.directories
}
