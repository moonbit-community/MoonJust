///|
#borrow(path)
extern "C" fn file_size_ffi(path : Bytes) -> Int64 = "moonjust_host_file_size"

///|
#borrow(path)
extern "C" fn read_file_range_ffi(
  path : Bytes,
  offset : Int64,
  length : Int,
) -> Bytes = "moonjust_host_read_file_range"

///|
fn file_size_value(value : String) -> Int64? {
  let size = file_size_ffi(@utf8.encode(value))
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
  let bytes = read_file_range_ffi(@utf8.encode(value), offset, length)
  if length > 0 && bytes.is_empty() {
    None
  } else {
    Some(bytes)
  }
}
