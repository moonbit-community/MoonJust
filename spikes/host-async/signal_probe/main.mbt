///|
extern "C" fn install_signal_probe() = "moonjust_async_install_signal_probe"

///|
extern "C" fn signal_probe_seen() -> Int = "moonjust_async_signal_probe_seen"

///|
fn init {
  @signal.set_global_cancellation_signals([])
  install_signal_probe()
}

///|
async fn main {
  @async.sleep(500)
  if signal_probe_seen() != 0 {
    println("custom-handler")
  } else {
    println("no-signal")
  }
}
