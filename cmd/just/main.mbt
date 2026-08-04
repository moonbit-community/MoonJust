///|
fn main {
  let args = @env.args()
  if args.contains("--version") || args.contains("-V") {
    println(@moonjust.version_line())
  } else {
    println("MoonJust is in Phase 0 and cannot execute justfiles yet.")
    println("Run with --version to inspect the compatibility baseline.")
  }
}
