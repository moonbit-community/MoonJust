///|
/// Persist bytes through a same-directory temporary file. Adapters must create
/// the temporary file exclusively and commit it atomically. A failed commit is
/// followed by a best-effort cleanup without hiding the original failure.
pub fn[T : @host.HostFs + @host.HostTemp] write_file_atomic(
  host : T,
  path : @path.PathValue,
  contents : Bytes,
  overwrite? : Bool = true,
) -> Unit raise @host.HostError {
  let directory = match path.parent() {
    Some(value) => value
    None =>
      raise InvalidInput("atomic write target must have a parent directory")
  }
  let temporary = @host.HostTemp::create_temp_file(
    host, directory, ".moonjust.tmp.", contents,
  )
  errdefer (try @host.HostTemp::remove_temp_file(host, temporary) catch {
    _ => ()
  } noraise {
    _ => ()
  })
  @host.HostFs::persist_temp_file(host, temporary, path, overwrite)
}
