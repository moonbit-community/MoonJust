///|
#derive(Eq, Hash)
priv struct GraphNodeKey {
  canonical_path : @path.PathValue
  module_path : @modulepath.ModulePath
}
