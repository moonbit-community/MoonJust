///|
pub impl @host.HostClock for NativeFs with fn now_millis(_self : NativeFs) -> Int64 raise @host.HostError {
  raise CapabilityUnavailable(Clock)
}
