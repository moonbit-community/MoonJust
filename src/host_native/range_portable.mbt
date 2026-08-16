///|
fn file_size_value(value : String) -> Int64? {
  let contents = @fs.read_file_to_bytes(value) catch { _ => return None }
  Some(contents.length().to_int64())
}

///|
fn file_executable_value(value : String) -> Bool {
  ignore(value)
  true
}

///|
fn read_file_range_value(
  value : String,
  offset : Int64,
  length : Int,
) -> Bytes? {
  if offset < 0L || length < 0 || offset > 0x7fff_ffffL {
    return None
  }
  let contents = @fs.read_file_to_bytes(value) catch { _ => return None }
  let start = offset.to_int()
  if start >= contents.length() {
    return Some(b"")
  }
  Some(contents[start:Int::min(contents.length(), start + length)].to_owned())
}

///|
fn read_file_stream_value(_value : String) -> Bytes? {
  None
}
