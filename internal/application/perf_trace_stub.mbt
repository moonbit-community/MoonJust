///|
/// The async stdio package is unavailable on JS and WasmGC. Keep the trace
/// hooks source-compatible while compiling those targets.
fn perf_detail_mark(_name : String) -> Unit {
  ()
}

///|
fn perf_detail_emit() -> Unit raise @host.HostError {
  if @async.now() < 0L {
    raise CapabilityUnavailable(Process)
  }
  ignore(@stdio.unimplemented)
}
