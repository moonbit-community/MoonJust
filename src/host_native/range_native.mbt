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
  RangeNativePath(@utf8.encode(value))
}

///|
#borrow(path)
extern "C" fn file_size_ffi(path : RangeNativePath) -> Int64 = "moonjust_host_file_size"

///|
#borrow(path)
extern "C" fn file_executable_ffi(path : RangeNativePath) -> Int = "moonjust_host_file_executable"

///|
#borrow(path)
extern "C" fn read_file_range_ffi(
  path : RangeNativePath,
  offset : Int64,
  length : Int,
) -> Bytes = "moonjust_host_read_file_range"

///|
#borrow(path)
extern "C" fn read_file_stream_ffi(path : RangeNativePath) -> Bytes = "moonjust_host_read_file_stream"

///|
fn file_size_value(value : String) -> Int64? {
  let size = file_size_ffi(RangeNativePath::new(value))
  if size < 0L {
    None
  } else {
    Some(size)
  }
}

///|
fn file_executable_value(value : String) -> Bool {
  file_executable_ffi(RangeNativePath::new(value)) != 0
}

///|
fn read_file_range_value(
  value : String,
  offset : Int64,
  length : Int,
) -> Bytes? {
  let bytes = read_file_range_ffi(RangeNativePath::new(value), offset, length)
  if length > 0 && bytes.is_empty() {
    None
  } else {
    Some(bytes)
  }
}

///|
fn read_file_stream_value(value : String) -> Bytes? {
  let encoded = read_file_stream_ffi(RangeNativePath::new(value))
  if encoded.is_empty() || encoded[0] != 1 {
    None
  } else {
    Some(encoded[1:].to_owned())
  }
}
