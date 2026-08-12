///|
/// Return the current MoonJust package version.
pub fn version() -> String {
  "0.7.0-alpha"
}

///|
/// Return the upstream `just` version used as the compatibility baseline.
pub fn compatible_just_version() -> String {
  "1.57.0"
}

///|
/// Render the version line used by the command-line entry point.
pub fn version_line() -> String {
  "moonjust \{version()} (compatible with just \{compatible_just_version()})"
}
