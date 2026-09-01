///|
// Keep the executable identity in one place. The module metadata is the
// release source of truth; this constant is updated with that value for the
// no-filesystem static invocation path.
const MOONJUST_VERSION : String = "0.1.2"

///|
fn version_line() -> String {
  "moonjust v" + MOONJUST_VERSION
}
