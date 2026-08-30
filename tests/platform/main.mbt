///|
fn candidate_path(args : ArrayView[String]) -> String? {
  for index, value in args {
    if value == "--candidate" && index + 1 < args.length() {
      return Some(args[index + 1])
    }
  }
  None
}

///|
async fn main {
  guard candidate_path(@env.args()[1:]) is Some(candidate) else {
    @stdio.stderr.write("Usage: moonjust-platform --candidate PATH\n")
    @sys.exit(2)
    return
  }
  let root = @fs.tmpdir(prefix="moonjust-platform")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let justfile = @path.Path(root).join(Path("justfile")).to_string()
  @fs.write_file(
    justfile,
    @utf8.encode("probe:\n  @echo {{invocation_directory()}}\n"),
  )
  let result = @testkit.run(
    candidate,
    ["--justfile", justfile, "--dry-run", "probe"],
    cwd=root,
  )
  let stdout = @utf8.decode(result.stdout) catch { _ => "" }
  let stderr = @utf8.decode(result.stderr) catch { _ => "" }
  let output = stdout + stderr
  if result.status != 0 || !output.contains("invocation_directory()") {
    @stdio.stderr.write("platform boundary check failed\n")
    @sys.exit(1)
    return
  }
  @stdio.stdout.write("MoonJust platform boundary checks passed.\n")
}
