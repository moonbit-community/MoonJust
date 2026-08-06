///|
/// Native/wasm filesystem adapter backed by the approved `moonbitlang/x/fs`
/// package. Core packages depend only on `@host.HostFs` and never on this leaf.
pub struct NativeFs {}

///|
pub fn NativeFs::new() -> NativeFs {
  NativeFs::{  }
}

///|
fn io_error(error : @fs.IOError) -> @host.HostError {
  match error {
    @fs.IOError(detail) => @host.InvalidInput(detail)
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
    let size = @fs.read_file_to_bytes(value) catch {
      error => raise io_error(error)
    }
    @host.FileMetadata::new(true, false, size.length().to_int64())
  } else if is_directory {
    @host.FileMetadata::new(false, true, 0L)
  } else {
    raise @host.NotFound(path)
  }
}

///|
pub impl @host.HostFs for NativeFs with fn canonicalize(
  _self : NativeFs,
  path : @path.PathValue,
) -> @path.PathValue raise @host.HostError {
  // x/fs intentionally exposes portable file operations, not realpath. The
  // adapter still provides one canonical identity boundary; native realpath
  // can be added without changing loader or semantic APIs.
  path
}
