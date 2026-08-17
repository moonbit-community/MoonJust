///|
async fn read_bounded_source_native(
  path : @path.PathValue,
  max_bytes : Int,
) -> Bytes raise @host.HostError {
  if max_bytes < 0 {
    raise InvalidInput("source byte limit must not be negative")
  }
  if max_bytes == 0x7fffffff {
    raise InvalidInput("source byte limit is too large")
  }
  let file = @async_fs.open(path.as_string(), mode=ReadOnly) catch {
    error => raise InvalidInput("source open failed: " + error.to_string())
  }
  defer file.close()
  let read_limit = max_bytes + 1
  let probed_size = file.size() catch { _ => 0L }
  let size_hint = if probed_size > 0L && probed_size < read_limit.to_int64() {
    probed_size.to_int()
  } else {
    Int::min(read_limit, 64 * 1024)
  }
  let result = Buffer(size_hint~)
  // Continue to the hard limit even when the size probe was smaller: the file
  // may grow between the probe and the final read.
  while result.length() < read_limit {
    let remaining = read_limit - result.length()
    let chunk = file.read_some(max_len=Int::min(remaining, 64 * 1024)) catch {
      error => raise InvalidInput("source read failed: " + error.to_string())
    }
    guard chunk is Some(chunk) else { break }
    if chunk.is_empty() {
      break
    }
    result.write_bytes(chunk)
  }
  result.to_bytes()
}

///|
pub impl @host.HostSourceReader for NativeFs with fn read_source(
  _self : NativeFs,
  path : @path.PathValue,
  max_bytes : Int,
) -> Bytes raise @host.HostError {
  read_bounded_source_native(path, max_bytes)
}
