///|
/// Configure the process signals that async uses to cancel the root task.
/// Signal events are intentionally not observed or forwarded by MoonJust.
pub fn configure_cancellation_signals() -> Unit {
  @signal.set_global_cancellation_signals([SIGINT, SIGTERM, SIGHUP, SIGBREAK])
}
