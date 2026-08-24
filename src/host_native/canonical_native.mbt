///|
#external
priv type NativePathPointer

///|
#borrow(pointer)
extern "C" fn native_path_pointer_is_null(pointer : NativePathPointer) -> Int = "moonbitlang_x_fs_is_null"

///|
extern "C" fn native_buffer_new(size : Int) -> NativePathPointer = "moonbitlang_async_make_c_buffer"

///|
#borrow(pointer)
extern "C" fn native_buffer_length(
  pointer : NativePathPointer,
  offset : Int,
) -> Int = "moonbitlang_async_strlen"

///|
#borrow(pointer, destination)
extern "C" fn native_buffer_copy(
  pointer : NativePathPointer,
  source_offset : Int,
  destination : FixedArray[Byte],
  destination_offset : Int,
  length : Int,
) -> Unit = "moonbitlang_async_blit_from_c"

///|
extern "C" fn native_buffer_free(pointer : NativePathPointer) -> Unit = "free"

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
      Some("\\\\" + resolved[8:].to_owned())
    } else if resolved.has_prefix("\\\\?\\") {
      Some(resolved[4:].to_owned())
    } else {
      Some(resolved)
    }
  }
}

///|
#cfg(all(target="native", platform="linux"))
#borrow(path)
extern "C" fn native_realpath(path : Bytes) -> NativePathPointer = "canonicalize_file_name"

///|
#cfg(all(target="native", not(platform="windows"), not(platform="linux")))
#borrow(path, resolved)
extern "C" fn native_realpath(
  path : Bytes,
  resolved : NativePathPointer,
) -> NativePathPointer = "realpath$DARWIN_EXTSN"

///|

///|
#cfg(platform="linux")
fn native_realpath_bytes(path : Bytes) -> Bytes? {
  let pointer = native_realpath(path)
  if native_path_pointer_is_null(pointer) != 0 {
    None
  } else {
    let length = native_buffer_length(pointer, 0)
    let resolved : FixedArray[Byte] = FixedArray::make(length, 0)
    native_buffer_copy(pointer, 0, resolved, 0, length)
    native_buffer_free(pointer)
    Some(resolved.unsafe_reinterpret_as_bytes())
  }
}

///|
#cfg(all(not(platform="windows"), not(platform="linux")))
fn native_realpath_bytes(path : Bytes) -> Bytes? {
  let buffer = native_buffer_new(32768)
  let pointer = native_realpath(path, buffer)
  if native_path_pointer_is_null(pointer) != 0 {
    native_buffer_free(buffer)
    None
  } else {
    let length = native_buffer_length(pointer, 0)
    let resolved : FixedArray[Byte] = FixedArray::make(length, 0)
    native_buffer_copy(pointer, 0, resolved, 0, length)
    native_buffer_free(buffer)
    Some(resolved.unsafe_reinterpret_as_bytes())
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
fn canonical_path_string(value : String) -> String? {
  let path = @utf8.encode(value) + Bytes::make(1, (0).to_byte())
  let decoded : String? = match native_realpath_bytes(path) {
    Some(resolved) => Some(@utf8.decode(resolved)) catch { _ => None }
    None => None
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
