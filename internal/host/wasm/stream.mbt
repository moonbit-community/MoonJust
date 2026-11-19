///|
pub impl @host.HostFs for ExecutionFs with fn stream_regular_file(
  self,
  path,
  chunk_size,
  consume,
) -> @host.FileMetadata raise @host.HostError {
  if chunk_size <= 0 {
    raise InvalidInput("chunk size must be positive")
  }
  // Opening a named pipe may wait for a writer. Screen special paths before
  // opening, then use the opened object's own kind and size for every read.
  let metadata = self.metadata(path)
  if !metadata.is_file() {
    return metadata
  }
  stream_open_file(
    path,
    chunk_size,
    consume,
    () => @async_fs.open(path.as_string(), mode=ReadOnly),
    (file, buffer, limit) => file.read_into(buffer, max_len=limit),
  )
}

///|
/// Open once, then bound every read by the size observed on that handle.
/// Passing the two I/O operations explicitly lets tests force a short read
/// or rebind the path between actual file reads.
async fn stream_open_file(
  path : @path.PathValue,
  chunk_size : Int32,
  consume : (Bytes) -> Unit,
  open_file : async () -> @async_fs.File,
  read : async (@async_fs.File, FixedArray[Byte], Int32) -> Int32,
) -> @host.FileMetadata raise @host.HostError {
  let file = open_file() catch { error => raise read_error(error, path) }
  defer file.close()
  let kind = file.kind()
  if kind != Regular {
    return @host.FileMetadata::new(false, kind == Directory)
  }
  let size = file.size() catch { error => raise read_error(error, path) }
  if size == 0L {
    consume(b"")
    return @host.FileMetadata::new(true, false)
  }
  let capacity = Int64::min(size, chunk_size.to_int64()).to_int()
  let buffer = FixedArray::make(capacity, b'\x00')
  for remaining = size; remaining > 0L; {
    let limit = Int64::min(remaining, capacity.to_int64()).to_int()
    let count = read(file, buffer, limit) catch {
      error => raise read_error(error, path)
    }
    if count <= 0 || count > limit {
      raise InvalidInput("host returned an invalid file range")
    }
    consume(Bytes::from_array(buffer[:count]))
    continue remaining - count.to_int64()
  }
  @host.FileMetadata::new(true, false)
}
