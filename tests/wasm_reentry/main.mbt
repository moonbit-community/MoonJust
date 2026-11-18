///|
async fn main {
  let args = @env.args()[1:]
  guard @env.get_env_var("MOONJUST_WASM_CANDIDATE") is Some(wasm) else {
    @stdio.stderr.text.write("missing Wasm candidate\n")
    @env.exit(2)
  }
  @env.exit(
    @process.run(
      @env.get_env_var("MOONJUST_MOONRUN").unwrap_or("moonrun"),
      [wasm, "--", ..args],
      stdin=Inherit,
      stdout=Inherit,
      stderr=Inherit,
    ).exit_code,
  )
}
