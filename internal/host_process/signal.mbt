///|
/// Configure the process signals that async uses to cancel the root task.
/// Signal events are intentionally not observed or forwarded by MoonJust.
fn configure_async_signal_policy() -> Unit {
  @signal.set_global_cancellation_signals([SIGINT, SIGTERM, SIGHUP, SIGBREAK])
}

///|
pub fn prepare_signal_forwarding() -> Unit {
  configure_async_signal_policy()
}

///|
pub fn[X] configure_signal_forwarding(
  group : @async.TaskGroup[X],
  observe_children : Bool,
) -> @host.HostError? {
  ignore(group)
  ignore(observe_children)
  configure_async_signal_policy()
  None
}

///|
/// Raw signal observation is not part of the async-only compatibility surface.
pub async fn wait_for_signal_request() -> String? {
  @async.sleep(0)
  None
}
