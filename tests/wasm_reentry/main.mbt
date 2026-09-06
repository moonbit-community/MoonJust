///|
#cfg(platform="windows")
extern "C" fn native_set_file_mode(fd : Int, mode : Int) -> Int = "_setmode"

///|
#cfg(platform="windows")
fn init {
  ignore(native_set_file_mode(1, 0x8000))
  ignore(native_set_file_mode(2, 0x8000))
}

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
  let child = match @env.get_env_var("MOONJUST_MOONX") {
    Some(moonx) if !moonx.is_empty() =>
      @process.collect_output(
        moonx,
        [
          "--target",
          @env.get_env_var("MOONJUST_MOONX_TARGET").unwrap_or("wasm"),
          wasm,
          ..args,
        ],
        inherit_env=true,
        no_console_window=true,
      )
    _ =>
      @process.collect_output(
        runner,
        [wasm, "--", ..args],
        inherit_env=true,
        no_console_window=true,
      )
  }
  @stdio.stdout.write(child.1)
  @stdio.stderr.write(child.2)
  @sys.exit(child.0)
}
