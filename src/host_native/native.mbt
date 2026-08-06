///|
/// Native/wasm filesystem adapter backed by the approved `moonbitlang/x/fs`
/// package. Core packages depend only on `@host.HostFs` and never on this leaf.
pub struct NativeFs {
  marker : Unit
}

///|
pub fn NativeFs::new() -> NativeFs {
  { marker: () }
}

///|
fn io_error(error : @fs.IOError) -> @host.HostError {
  match error {
    IOError(detail) => InvalidInput(detail)
  }
}

///|
pub impl @host.HostFs for NativeFs with fn read_file(
  _self : NativeFs,
  path : @path.PathValue,
) -> Bytes raise @host.HostError {
  @fs.read_file_to_bytes(path.as_string()) catch {
    error => raise io_error(error)
  }
}

///|
pub impl @host.HostFs for NativeFs with fn read_file_range(
  _self : NativeFs,
  path : @path.PathValue,
  offset : Int64,
  length : Int,
) -> Bytes raise @host.HostError {
  if offset < 0L || length < 0 {
    raise InvalidInput("file range must not be negative")
  }
  match read_file_range_value(path.as_string(), offset, length) {
    Some(bytes) => bytes
    None => raise CapabilityUnavailable(FsRead)
  }
}

///|
pub impl @host.HostFs for NativeFs with fn write_file(
  _self : NativeFs,
  path : @path.PathValue,
  contents : Bytes,
) -> Unit raise @host.HostError {
  @fs.write_bytes_to_file(path.as_string(), contents) catch {
    error => raise io_error(error)
  }
}

///|
pub impl @host.HostFs for NativeFs with fn file_exists(
  _self : NativeFs,
  path : @path.PathValue,
) -> Bool raise @host.HostError {
  @fs.path_exists(path.as_string())
}

///|
pub impl @host.HostFs for NativeFs with fn read_dir(
  _self : NativeFs,
  path : @path.PathValue,
) -> Array[String] raise @host.HostError {
  @fs.read_dir(path.as_string()) catch {
    error => raise io_error(error)
  }
}

///|
pub impl @host.HostFs for NativeFs with fn metadata(
  _self : NativeFs,
  path : @path.PathValue,
) -> @host.FileMetadata raise @host.HostError {
  let value = path.as_string()
  let is_file = @fs.is_file(value) catch { error => raise io_error(error) }
  let is_directory = @fs.is_dir(value) catch { error => raise io_error(error) }
  if is_file {
    let size = match file_size_value(value) {
      Some(size) => size
      None => raise CapabilityUnavailable(FsRead)
    }
    @host.FileMetadata::new(true, false, size)
  } else if is_directory {
    @host.FileMetadata::new(false, true, 0L)
  } else {
    raise NotFound(path)
  }
}

///|
pub impl @host.HostFs for NativeFs with fn canonicalize(
  _self : NativeFs,
  path : @path.PathValue,
) -> @path.PathValue raise @host.HostError {
  match canonical_path_string(path.as_string()) {
    None => raise NotFound(path)
    Some(value) =>
      @path.PathValue::new(value, path.flavor()) catch {
        _ => raise InvalidInput("canonical path has an invalid representation")
      }
  }
}
