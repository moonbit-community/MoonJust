///|
fn option(args : ArrayView[String], name : String) -> String? {
  for index, value in args {
    if value == name && index + 1 < args.length() {
      return Some(args[index + 1])
    }
  }
  None
}

///|
async fn platform_result(program : String) -> @testkit.RunResult {
  let root = @fs.tmpdir(prefix="moonjust-platform")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let justfile = @path.Path(root).join(Path("justfile")).to_string()
  @fs.write_file(
    justfile,
    @utf8.encode("probe:\n  @echo {{invocation_directory()}}\n"),
  )
  let result = @testkit.run(
    program,
    ["--justfile", justfile, "probe"],
    cwd=root,
  )
  {
    status: result.status,
    stdout: @testkit.replace_bytes(
      result.stdout,
      @utf8.encode(root)[:],
      b"<CASE_ROOT>"[:],
    ),
    stderr: @testkit.replace_bytes(
      result.stderr,
      @utf8.encode(root)[:],
      b"<CASE_ROOT>"[:],
    ),
  }
}

///|
async fn main {
  let args = @env.args()[1:]
  guard option(args, "--candidate") is Some(candidate) &&
    option(args, "--official") is Some(official) else {
    @stdio.stderr.write(
      "Usage: moonjust-platform --candidate PATH --official PATH\n",
    )
    @sys.exit(2)
    return
  }
  let expected = platform_result(official)
  let actual = platform_result(candidate)
  let failures : Array[String] = []
  if expected.status != actual.status {
    failures.push("exit status")
  }
  if !@testkit.bytes_equal(expected.stdout, actual.stdout) {
    failures.push("stdout")
  }
  if !@testkit.bytes_equal(expected.stderr, actual.stderr) {
    failures.push("stderr")
  }
  if !failures.is_empty() {
    @stdio.stderr.write(
      "platform differential failed: " + failures.join(", ") + "\n",
    )
    @sys.exit(1)
    return
  }
  @stdio.stdout.write("MoonJust platform differential passed.\n")
}
