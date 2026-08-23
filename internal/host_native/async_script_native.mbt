///|
pub impl @host.HostAsyncScriptTemp for NativeFs with fn create_script_temp_async(
  self : NativeFs,
  directory : @path.PathValue,
  stem : String,
  extension : String,
  contents : Bytes,
  executable : Bool,
) -> @path.PathValue raise @host.HostError {
  for _ in 0..<128 {
    let child = @path.PathValue::new(
      "just" + random_suffix(),
      directory.flavor(),
    ) catch {
      _ => raise InvalidInput("invalid temporary script directory")
    }
    let temporary_directory = directory.join(child) catch {
      _ => raise InvalidInput("temporary script directory flavor mismatch")
    }
    try
      @async_fs.mkdir(
        temporary_directory.as_string(),
        permission=0o700,
        recursive=false,
      )
    catch {
      @os_error.OSError(_) as error if error.is_EEXIST() => continue
      _ => raise InvalidInput("failed to create temporary script directory")
    } noraise {
      _ => ()
    }
    let path = {
      errdefer (try @async_fs.rmdir(temporary_directory.as_string()) catch {
        _ => ()
      } noraise {
        _ => ()
      })
      @host.HostScriptTemp::create_script_temp(
        self, temporary_directory, stem, extension, contents,
      )
    }
    if executable {
      errdefer {
        try @host.HostScriptTemp::remove_script_temp(self, path) catch {
          _ => ()
        } noraise {
          _ => ()
        }
        try @async_fs.rmdir(temporary_directory.as_string()) catch {
          _ => ()
        } noraise {
          _ => ()
        }
      }
      @host.HostExecutable::set_executable(self, path)
    }
    return path
  }
  raise InvalidInput("temporary script directory namespace exhausted")
}

///|
pub impl @host.HostAsyncScriptTemp for NativeFs with fn remove_script_temp_async(
  self : NativeFs,
  path : @path.PathValue,
) -> Unit raise @host.HostError {
  let parent = path.parent()
  @host.HostScriptTemp::remove_script_temp(self, path)
  match parent {
    Some(directory) =>
      try @async_fs.rmdir(directory.as_string()) catch {
        _ => raise InvalidInput("failed to remove temporary script directory")
      } noraise {
        _ => ()
      }
    None => ()
  }
}
