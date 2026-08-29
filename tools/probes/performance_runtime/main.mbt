///|
#warnings("-unused_async")
async fn main {
  let arguments = @env.args()
  guard arguments.get(1) is Some(mode) else {
    abort("expected static, env-get, env-all, or cwd")
  }
  let observed = match mode {
    "static" => arguments.length()
    "env-get" =>
      @env.get_env_var("MOONJUST_OS").map_or(0, value => value.length())
    "env-all" => {
      let mut count = 0
      for _, _ in @env.get_env_vars() {
        count += 1
      }
      count
    }
    "cwd" => @env.current_dir().map_or(0, value => value.length())
    _ => abort("expected static, env-get, env-all, or cwd")
  }
  if observed < 0 {
    abort("invalid probe observation")
  }
  println(observed)
}
