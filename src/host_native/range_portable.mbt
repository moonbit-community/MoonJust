///|
fn file_size_value(value : String) -> Int64? {
  ignore(value)
  None
}

///|
fn read_file_range_value(
  value : String,
  offset : Int64,
  length : Int,
) -> Bytes? {
  ignore(value)
  ignore(offset)
  ignore(length)
  None
}
