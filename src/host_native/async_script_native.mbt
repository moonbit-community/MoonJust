///|
pub impl @host.HostAsyncScriptTemp for NativeFs with fn create_script_temp_async(
  self : NativeFs,
  directory : @path.PathValue,
  stem : String,
  extension : String,
  contents : Bytes,
  executable : Bool,
) -> @path.PathValue raise @host.HostError {
  let path = @host.HostScriptTemp::create_script_temp(
    self, directory, stem, extension, contents,
  )
  if executable {
    @host.HostExecutable::set_executable(self, path)
  }
  path
}

///|
pub impl @host.HostAsyncScriptTemp for NativeFs with fn remove_script_temp_async(
  self : NativeFs,
  path : @path.PathValue,
) -> Unit raise @host.HostError {
  @host.HostScriptTemp::remove_script_temp(self, path)
}
