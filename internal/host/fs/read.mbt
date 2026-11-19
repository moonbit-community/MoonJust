///|
/// Pull a file through a bounded buffer. The callback observes chunks in file
/// order and never receives more than `chunk_size` bytes.
pub async fn[T : @host.HostFs] stream_file(
  host : T,
  path : @path.PathValue,
  consume : (Bytes) -> Unit,
  chunk_size~ : Int32 = 64 * 1024,
) -> Unit raise @host.HostError {
  let metadata = @host.HostFs::stream_regular_file(
    host, path, chunk_size, consume,
  )
  if !metadata.is_file() {
    raise InvalidInput("stream source must be a file")
  }
}

///|
/// Compatibility collector for callers that explicitly need all chunks.
pub async fn[T : @host.HostFs] read_file_chunks(
  host : T,
  path : @path.PathValue,
  chunk_size~ : Int32 = 64 * 1024,
) -> Array[Bytes] raise @host.HostError {
  let chunks : Array[Bytes] = []
  stream_file(host, path, fn(bytes) { chunks.push(bytes) }, chunk_size~)
  chunks
}
