///|
#cfg(platform="windows")
#borrow(path)
extern "C" fn realpath_ffi(path : String) -> String = "moonjust_host_realpath"

///|
#cfg(platform="windows")
fn canonical_path_string(value : String) -> String? {
  let resolved = realpath_ffi(value)
  if resolved == "" {
    None
  } else {
    Some(resolved)
  }
}

///|
#cfg(not(platform="windows"))
#borrow(path)
extern "C" fn realpath_ffi(path : Bytes) -> Bytes = "moonjust_host_realpath"

///|
#cfg(not(platform="windows"))
fn canonical_path_string(value : String) -> String? {
  let resolved = realpath_ffi(@utf8.encode(value))
  if resolved.is_empty() {
    None
  } else {
    Some(@utf8.decode(resolved) catch { _ => return None })
  }
}
