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
extern "C" fn read_file_range_ffi(
  path : RangeNativePath,
  offset : Int64,
  length : Int,
) -> Bytes = "moonjust_host_read_file_range"

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
