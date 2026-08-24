///|
#external
priv type NativePathPointer

///|
#borrow(pointer)
extern "C" fn native_path_pointer_is_null(pointer : NativePathPointer) -> Int = "moonbitlang_x_fs_is_null"

///|
#cfg(platform="windows")
#external
priv type NativePathHandle

///|
#cfg(platform="windows")
#borrow(path)
extern "C" fn native_create_path_handle(
  path : String,
  access : UInt,
  share : UInt,
  security : Int,
  disposition : UInt,
  flags : UInt,
  template : Int,
) -> NativePathHandle = "CreateFileW"

///|
#cfg(platform="windows")
#borrow(handle, buffer)
extern "C" fn native_final_path(
  handle : NativePathHandle,
  buffer : String,
  capacity : UInt,
  flags : UInt,
) -> UInt = "GetFinalPathNameByHandleW"

///|
#cfg(platform="windows")
#borrow(handle)
extern "C" fn native_close_path_handle(handle : NativePathHandle) -> Int = "CloseHandle"

///|
#cfg(platform="windows")
fn canonical_path_string(value : String) -> String? {
  let handle = native_create_path_handle(value, 0, 7, 0, 3, 0x02000000, 0)
  let buffer = String::make(32768, '\u{0}')
  let length = native_final_path(handle, buffer, 32768, 0)
  if length == 0U || length >= 32768U {
    ignore(native_close_path_handle(handle))
    None
  } else {
    ignore(native_close_path_handle(handle))
    let resolved = buffer[:length.to_int()].to_owned()
    if resolved.has_prefix("\\\\?\\UNC\\") {
      Some("\\\\" + resolved[8:])
    } else if resolved.has_prefix("\\\\?\\") {
      Some(resolved[4:])
    } else {
      Some(resolved)
    }
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
#borrow(path, resolved)
extern "C" fn native_realpath(
  path : Bytes,
  resolved : Bytes,
) -> NativePathPointer = "realpath"

///|
#cfg(all(target="native", not(platform="windows")))
fn canonical_path_string(value : String) -> String? {
  let resolved = Bytes::make(32768, 0)
  let pointer = native_realpath(
    @utf8.encode(value) + Bytes::make(1, (0).to_byte()),
    resolved,
  )
  if native_path_pointer_is_null(pointer) != 0 {
    if native_cwd_nonunicode() && !value.has_prefix("/") {
      native_warn_nonunicode_justfile()
      Some(value)
    } else {
      None
    }
  } else {
    let mut length = 0
    while length < resolved.length() && resolved[length] != 0 {
      length += 1
    }
    let decoded : String? = Some(@utf8.decode(resolved[:length])) catch {
      _ => None
    }
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
