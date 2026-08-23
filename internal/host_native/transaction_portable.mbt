///|
fn create_native_temp(
  _directory : @path.PathValue,
  _prefix : String,
  _contents : Bytes,
) -> @path.PathValue raise @host.HostError {
  raise CapabilityUnavailable(FsWrite)
}

///|
fn create_native_script_temp(
  _directory : @path.PathValue,
  _stem : String,
  _extension : String,
  _contents : Bytes,
) -> @path.PathValue raise @host.HostError {
  raise CapabilityUnavailable(FsWrite)
}

///|
fn set_native_executable(_path : @path.PathValue) -> Unit raise @host.HostError {
  raise CapabilityUnavailable(FsWrite)
}

///|
fn persist_native_temp(
  _temporary : @path.PathValue,
  _destination : @path.PathValue,
  _overwrite : Bool,
) -> Unit raise @host.HostError {
  raise CapabilityUnavailable(FsWrite)
}
