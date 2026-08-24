///|
/// Return the current MoonJust package version.
pub fn version() -> String {
  "v0.1.0"
}

///|
/// Return the upstream `just` version used as the compatibility baseline.
pub fn just_compatibility_target() -> String {
  "1.57.0"
}

///|
/// Render the version line used by the command-line entry point.
pub fn version_line() -> String {
  "moonjust \{version()}"
}
