///|
/// Pull a file through a bounded buffer. The callback observes chunks in file
/// order and never receives more than `chunk_size` bytes.
pub fn[T : @host.HostFs] stream_file(
  host : T,
  path : @path.PathValue,
  consume : (Bytes) -> Unit,
  chunk_size? : Int = 64 * 1024,
) -> Unit raise @host.HostError {
  if chunk_size <= 0 {
    raise InvalidInput("chunk size must be positive")
  }
  let metadata = @host.HostFs::metadata(host, path)
  if !metadata.is_file() {
    raise InvalidInput("stream source must be a file")
  }
  let mut offset = 0L
  while offset < metadata.size() {
    let remaining = metadata.size() - offset
    let length = if remaining < chunk_size.to_int64() {
      remaining.to_int()
    } else {
      chunk_size
    }
    let bytes = @host.HostFs::read_file_range(host, path, offset, length)
    if bytes.length() == 0 || bytes.length() > length {
      raise InvalidInput("host returned an invalid file range")
    }
    consume(bytes)
    offset += bytes.length().to_int64()
  }
  if metadata.size() == 0L {
    consume(b"")
  }
}

///|
/// Compatibility collector for callers that explicitly need all chunks.
pub fn[T : @host.HostFs] read_file_chunks(
  host : T,
  path : @path.PathValue,
  chunk_size? : Int = 64 * 1024,
) -> Array[Bytes] raise @host.HostError {
  if chunk_size <= 0 {
    raise InvalidInput("chunk size must be positive")
  }
  let chunks : Array[Bytes] = []
  stream_file(host, path, fn(bytes) { chunks.push(bytes) }, chunk_size~)
  chunks
}
