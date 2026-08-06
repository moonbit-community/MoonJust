///|
#borrow(path)
extern "C" fn realpath_ffi(path : Bytes) -> Bytes = "moonjust_host_realpath"

///|
fn canonical_path_string(value : String) -> String? {
  let resolved = realpath_ffi(@utf8.encode(value))
  if resolved.is_empty() {
    None
  } else {
    Some(@utf8.decode(resolved) catch { _ => return None })
  }
}
