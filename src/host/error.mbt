///|
/// Errors crossing the host boundary. Adapter-specific errors must be mapped here.
pub(all) suberror HostError {
  CapabilityDenied(HostCapability)
  CapabilityUnavailable(HostCapability)
  NotFound(@path.PathValue)
  AlreadyExists(@path.PathValue)
  PermissionDenied(HostCapability, detail~ : String)
  InvalidInput(String)
  UnexpectedProcess(CommandSpec)
  ProcessMismatch(expected~ : CommandSpec, actual~ : CommandSpec)
  RandomExhausted(requested~ : Int, remaining~ : Int)
} derive(Eq, Debug)
