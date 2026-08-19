///|
#cfg(target="wasm")
async fn read_bounded_source_wasm(
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
  // `size()` is not a non-blocking operation for FIFOs on every host. Only
  // probe regular files; special files must go straight through bounded reads.
  let regular_file = @fs.is_file(path.as_string()) catch { _ => false }
  let probed_size = if regular_file {
    file.size() catch {
      _ => 0L
    }
  } else {
    0L
  }
  let size_hint = if probed_size > 0L && probed_size < read_limit.to_int64() {
    probed_size.to_int()
  } else {
    Int::min(read_limit, 64 * 1024)
  }
  let result = Buffer(size_hint~)
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
#cfg(target="wasm")
pub impl @host.HostSourceReader for NativeFs with fn read_source(
  _self : NativeFs,
  path : @path.PathValue,
  max_bytes : Int,
) -> Bytes raise @host.HostError {
  read_bounded_source_wasm(path, max_bytes)
}

///|
#cfg(target="wasm-gc")
pub impl @host.HostSourceReader for NativeFs with fn read_source(
  _self : NativeFs,
  path : @path.PathValue,
  max_bytes : Int,
) -> Bytes raise @host.HostError {
  if max_bytes < 0 {
    raise InvalidInput("source byte limit must not be negative")
  }
  if max_bytes == 0x7fffffff {
    raise InvalidInput("source byte limit is too large")
  }
  let contents = @fs.read_file_to_bytes(path.as_string()) catch {
    _ => raise InvalidInput("source read failed")
  }
  contents[:Int::min(contents.length(), max_bytes + 1)].to_owned()
}

///|
#cfg(target="js")
pub impl @host.HostSourceReader for NativeFs with fn read_source(
  _self : NativeFs,
  path : @path.PathValue,
  max_bytes : Int,
) -> Bytes raise @host.HostError {
  if max_bytes < 0 {
    raise InvalidInput("source byte limit must not be negative")
  }
  if max_bytes == 0x7fffffff {
    raise InvalidInput("source byte limit is too large")
  }
  let contents = @fs.read_file_to_bytes(path.as_string()) catch {
    _ => raise InvalidInput("source read failed")
  }
  contents[:Int::min(contents.length(), max_bytes + 1)].to_owned()
}
