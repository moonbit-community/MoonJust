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
#cfg(all(target="native", not(platform="windows")))
#borrow(path, buffer)
extern "C" fn native_readlink(
  path : Bytes,
  buffer : Bytes,
  length : Int,
) -> Int = "readlink"

///|
#cfg(all(target="native", not(platform="windows")))
fn native_readlink_value(value : String) -> String? {
  let buffer = Bytes::make(32768, 0)
  let path = @utf8.encode(value) + Bytes::make(1, (0).to_byte())
  let length = native_readlink(path, buffer, buffer.length())
  if length < 0 {
    None
  } else {
    Some(@utf8.decode(buffer[:length].to_owned())) catch {
      _ => None
    }
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
fn native_parent_path(value : String) -> String {
  let path = @path.PathValue::new(value, Unix) catch { _ => return "." }
  match path.parent() {
    Some(parent) => parent.as_string()
    None => "/"
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
fn native_unix_realpath(value : String) -> String? {
  let cwd = native_current_dir()
  let initial = if value.has_prefix("/") {
    value
  } else if cwd.is_empty() {
    value
  } else {
    cwd + "/" + value
  }
  let initial_path = @path.PathValue::new(initial, Unix) catch {
    _ => return None
  }
  let mut current = initial_path.as_string()
  for _ in 0..<40 {
    let components : Array[String] = []
    for component in current.split("/") {
      if !component.is_empty() {
        components.push("\{component}")
      }
    }
    let mut resolved = "/"
    let mut restart : String? = None
    for index, component in components {
      let candidate = if resolved == "/" {
        "/" + component
      } else {
        resolved + "/" + component
      }
      match native_readlink_value(candidate) {
        Some(target) => {
          let base = if target.has_prefix("/") {
            target
          } else {
            native_parent_path(candidate) + "/" + target
          }
          let suffix = if index + 1 < components.length() {
            "/" + components[index + 1:].join("/")
          } else {
            ""
          }
          restart = Some(base + suffix)
          break
        }
        None => {
          if !@fs.path_exists(candidate) {
            return None
          }
          resolved = candidate
        }
      }
    }
    match restart {
      None => return Some(resolved)
      Some(next) => {
        let next_path = @path.PathValue::new(next, Unix) catch {
          _ => return None
        }
        current = next_path.as_string()
      }
    }
  }
  None
}

///|
#cfg(all(target="native", not(platform="windows")))
fn canonical_path_string(value : String) -> String? {
  match native_unix_realpath(value) {
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
