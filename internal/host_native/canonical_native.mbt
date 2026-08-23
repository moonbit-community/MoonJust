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
#cfg(all(target="native", not(platform="windows")))
#borrow(path)
extern "C" fn realpath_ffi(path : Bytes) -> Bytes = "moonjust_host_realpath"

///|
#cfg(all(target="native", not(platform="windows")))
fn canonical_path_string(value : String) -> String? {
  let resolved = realpath_ffi(@utf8.encode(value))
  if resolved.is_empty() {
    if native_cwd_nonunicode() && !value.has_prefix("/") {
      native_warn_nonunicode_justfile()
      Some(value)
    } else {
      None
    }
  } else {
    let decoded : String? = Some(@utf8.decode(resolved)) catch { _ => None }
    match decoded {
      Some(result) => Some(result)
      None =>
        if native_cwd_nonunicode() && !value.has_prefix("/") {
          native_warn_nonunicode_justfile()
          Some(value)
        } else {
          None
        }
    }
  }
}
