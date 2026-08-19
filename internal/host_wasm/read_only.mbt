///|
/// Filesystem adapter for Wasm inspection. It deliberately exposes no process,
/// environment, clock, random, terminal, or signal capability.
pub struct ReadOnlyFs {
  inner : @host_native.NativeFs
}

///|
pub fn ReadOnlyFs::new() -> ReadOnlyFs {
  { inner: @host_native.NativeFs::new() }
}

///|
pub impl @host.HostSourceReader for ReadOnlyFs with fn read_source(
  self : ReadOnlyFs,
  path : @path.PathValue,
  max_bytes : Int,
) -> Bytes raise @host.HostError {
  @host.HostSourceReader::read_source(self.inner, path, max_bytes)
}

///|
pub impl @host.HostFs for ReadOnlyFs with fn read_file(
  self : ReadOnlyFs,
  path : @path.PathValue,
) -> Bytes raise @host.HostError {
  @host.HostFs::read_file(self.inner, path)
}

///|
pub impl @host.HostFs for ReadOnlyFs with fn read_file_range(
  self : ReadOnlyFs,
  path : @path.PathValue,
  offset : Int64,
  length : Int,
) -> Bytes raise @host.HostError {
  if offset < 0L || length < 0 || offset > 0x7fff_ffffL {
    raise InvalidInput("file range must be representable and non-negative")
  }
  let contents = @host.HostFs::read_file(self.inner, path)
  let start = offset.to_int()
  if start >= contents.length() {
    return b""
  }
  contents[start:Int::min(contents.length(), start + length)].to_owned()
}

///|
pub impl @host.HostFs for ReadOnlyFs with fn write_file(
  _self : ReadOnlyFs,
  _path : @path.PathValue,
  _contents : Bytes,
) -> Unit raise @host.HostError {
  raise CapabilityDenied(FsWrite)
}

///|
pub impl @host.HostFs for ReadOnlyFs with fn file_exists(
  self : ReadOnlyFs,
  path : @path.PathValue,
) -> Bool raise @host.HostError {
  @host.HostFs::file_exists(self.inner, path)
}

///|
pub impl @host.HostFs for ReadOnlyFs with fn read_dir(
  self : ReadOnlyFs,
  path : @path.PathValue,
) -> Array[String] raise @host.HostError {
  @host.HostFs::read_dir(self.inner, path)
}

///|
pub impl @host.HostFs for ReadOnlyFs with fn metadata(
  self : ReadOnlyFs,
  path : @path.PathValue,
) -> @host.FileMetadata raise @host.HostError {
  // Metadata must not read the file: a FIFO or other special file can block
  // until a writer appears. The native adapter already uses non-consuming
  // type checks and reports special files without a size probe.
  @host.HostFs::metadata(self.inner, path)
}

///|
pub impl @host.HostFs for ReadOnlyFs with fn canonicalize(
  self : ReadOnlyFs,
  path : @path.PathValue,
) -> @path.PathValue raise @host.HostError {
  @host.HostFs::canonicalize(self.inner, path)
}

///|
pub impl @host.HostFs for ReadOnlyFs with fn persist_temp_file(
  _self : ReadOnlyFs,
  _temporary : @path.PathValue,
  _destination : @path.PathValue,
  _overwrite : Bool,
) -> Unit raise @host.HostError {
  raise CapabilityDenied(FsWrite)
}

///|
pub impl @host.HostTemp for ReadOnlyFs with fn create_temp_file(
  _self : ReadOnlyFs,
  _directory : @path.PathValue,
  _prefix : String,
  _contents : Bytes,
) -> @path.PathValue raise @host.HostError {
  raise CapabilityDenied(FsWrite)
}

///|
pub impl @host.HostTemp for ReadOnlyFs with fn remove_temp_file(
  _self : ReadOnlyFs,
  _path : @path.PathValue,
) -> Unit raise @host.HostError {
  raise CapabilityDenied(FsWrite)
}

///|
pub impl @host.HostAtomicFs for ReadOnlyFs with fn write_file_atomic(
  _self : ReadOnlyFs,
  _path : @path.PathValue,
  _contents : Bytes,
  _overwrite : Bool,
) -> Unit raise @host.HostError {
  raise CapabilityDenied(FsWrite)
}
