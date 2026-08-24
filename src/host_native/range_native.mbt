///|
#cfg(platform="windows")
priv struct RangeNativePath(String)

///|
#cfg(not(platform="windows"))
priv struct RangeNativePath(Bytes)

///|
#cfg(platform="windows")
fn RangeNativePath::new(value : String) -> RangeNativePath {
  RangeNativePath(value)
}

///|
#cfg(not(platform="windows"))
fn RangeNativePath::new(value : String) -> RangeNativePath {
  RangeNativePath(@utf8.encode(value) + Bytes::make(1, (0).to_byte()))
}

///|
#external
priv type NativeFileHandle

///|
#borrow(file)
extern "C" fn native_file_is_null(file : NativeFileHandle) -> Int = "moonbitlang_x_fs_is_null"

///|
#cfg(platform="windows")
#borrow(path, mode)
extern "C" fn native_open_file(
  path : String,
  mode : String,
) -> NativeFileHandle = "_wfopen"

///|
#cfg(not(platform="windows"))
#borrow(path, mode)
extern "C" fn native_open_file(path : Bytes, mode : Bytes) -> NativeFileHandle = "fopen"

///|
#borrow(file)
extern "C" fn native_close_file(file : NativeFileHandle) -> Int = "fclose"

///|
#cfg(platform="windows")
#borrow(file)
extern "C" fn native_seek_file(
  file : NativeFileHandle,
  offset : Int64,
  whence : Int,
) -> Int = "_fseeki64"

///|
#cfg(not(platform="windows"))
#borrow(file)
extern "C" fn native_seek_file(
  file : NativeFileHandle,
  offset : Int64,
  whence : Int,
) -> Int = "fseeko"

///|
#cfg(platform="windows")
#borrow(file)
extern "C" fn native_tell_file(file : NativeFileHandle) -> Int64 = "_ftelli64"

///|
#cfg(not(platform="windows"))
#borrow(file)
extern "C" fn native_tell_file(file : NativeFileHandle) -> Int64 = "ftello"

///|
#borrow(buffer, file)
extern "C" fn native_read_file(
  buffer : Bytes,
  size : Int,
  count : Int,
  file : NativeFileHandle,
) -> Int = "fread"

///|
#cfg(platform="windows")
#borrow(path)
extern "C" fn native_access(path : String, mode : Int) -> Int = "_waccess"

///|
#cfg(not(platform="windows"))
#borrow(path)
extern "C" fn native_access(path : Bytes, mode : Int) -> Int = "access"

///|
#cfg(platform="windows")
fn native_open_read(path : RangeNativePath) -> NativeFileHandle {
  match path {
    RangeNativePath(path) => native_open_file(path, "rb")
  }
}

///|
#cfg(not(platform="windows"))
fn native_open_read(path : RangeNativePath) -> NativeFileHandle {
  match path {
    RangeNativePath(path) =>
      native_open_file(path, b"rb" + Bytes::make(1, (0).to_byte()))
  }
}

///|
fn file_size_value(value : String) -> Int64? {
  let path = RangeNativePath::new(value)
  let file = native_open_read(path)
  guard native_file_is_null(file) == 0 else { return None }
  defer ignore(native_close_file(file))
  guard native_seek_file(file, 0L, 2) == 0 else { return None }
  let size = native_tell_file(file)
  if size < 0L {
    None
  } else {
    Some(size)
  }
}

///|
fn file_executable_value(value : String) -> Bool {
  let path = RangeNativePath::new(value)
  native_access_value(path)
}

///|
fn read_file_range_value(
  value : String,
  offset : Int64,
  length : Int,
) -> Bytes? {
  guard offset >= 0L && length >= 0 else { return None }
  let path = RangeNativePath::new(value)
  let file = native_open_read(path)
  guard native_file_is_null(file) == 0 else { return None }
  defer ignore(native_close_file(file))
  guard native_seek_file(file, offset, 0) == 0 else { return None }
  let buffer = Bytes::make(length, 0)
  let count = native_read_file(buffer, 1, length, file)
  if count < 0 {
    None
  } else {
    Some(buffer[:Int::min(count, length)].to_owned())
  }
}

///|
// Special files such as FIFOs cannot be seeked. Read them as a stream so the
// first open is also the only open; reopening after a failed size probe would
// lose a one-shot writer and turn a valid source into a misleading access
// error.
fn read_nonregular_file_stream_value(value : String) -> Bytes? {
  let path = RangeNativePath::new(value)
  let file = native_open_read(path)
  guard native_file_is_null(file) == 0 else { return None }
  defer ignore(native_close_file(file))
  let result = Buffer()
  while true {
    let chunk = Bytes::make(64 * 1024, 0)
    let count = native_read_file(chunk, 1, chunk.length(), file)
    if count < 0 {
      return None
    }
    if count == 0 {
      break
    }
    result.write_bytes(chunk[:count])
  }
  Some(result.to_bytes())
}

///|
#cfg(platform="windows")
fn native_access_value(path : RangeNativePath) -> Bool {
  match path {
    RangeNativePath(path) => native_access(path, 0) == 0
  }
}

///|
#cfg(not(platform="windows"))
fn native_access_value(path : RangeNativePath) -> Bool {
  match path {
    RangeNativePath(path) => native_access(path, 1) == 0
  }
}

///|
fn read_file_stream_value(value : String) -> Bytes? {
  let regular_file = @fs.is_file(value) catch { _ => false }
  if !regular_file {
    return read_nonregular_file_stream_value(value)
  }
  Some(@fs.read_file_to_bytes(value) catch { _ => return None })
}
