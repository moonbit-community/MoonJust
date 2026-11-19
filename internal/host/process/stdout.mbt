///|
/// A closed stdout consumer has finished reading. Keep errors on all other
/// writes observable, including stderr and failed writes to regular files.
pub async fn write_stdout(bytes : BytesView) -> Unit raise @io.WriterError {
  @stdio.stdout.write(bytes) catch {
    TransportError(@os_error.OsError(_, raw_code~, ..), ..) as error => {
      let broken_pipe = if @async.platform is Windows {
        // ERROR_BROKEN_PIPE and ERROR_NO_DATA on a closing pipe.
        raw_code == 109 || raw_code == 232
      } else {
        // EPIPE on the supported Unix hosts.
        raw_code == 32
      }
      if !broken_pipe {
        raise error
      }
    }
    error => raise error
  }
}
