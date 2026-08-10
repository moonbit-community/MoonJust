///|
extern "c" fn native_now_millis() -> Int64 = "moonjust_host_now_millis"

///|
pub impl @host.HostClock for NativeFs with fn now_millis(_self : NativeFs) -> Int64 raise @host.HostError {
  let value = native_now_millis()
  if value < 0L {
    raise CapabilityUnavailable(Clock)
  }
  value
}
