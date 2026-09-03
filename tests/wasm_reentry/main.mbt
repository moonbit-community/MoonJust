///|
async fn main {
  let args = @env.args()[1:]
  let wasm = @env.get_env_var("MOONJUST_WASM_CANDIDATE").unwrap_or("")
  if wasm.is_empty() {
    @stdio.stderr.write("moonjust-wasm-reentry: missing candidate\n")
    @sys.exit(2)
    return
  }
  let runner = @env.get_env_var("MOONJUST_MOONRUN").unwrap_or("moonrun")
  let child = @process.collect_output(
    runner,
    [wasm, "--", ..args],
    inherit_env=true,
    no_console_window=true,
  )
  @stdio.stdout.write(child.1)
  @stdio.stderr.write(child.2)
  @sys.exit(child.0)
}
