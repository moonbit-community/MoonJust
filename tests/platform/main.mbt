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
async fn platform_result(
  program : String,
  justfile : String,
  cwd : String,
) -> @testkit.RunResult {
  @testkit.run(program, ["--justfile", justfile, "probe"], cwd~)
}

///|
fn describe(label : String, bytes : Bytes) -> String {
  let text = @utf8.decode(bytes) catch { _ => "<non-utf8>" }
  label +
  " length=" +
  bytes.length().to_string() +
  " sha256=" +
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes)) +
  " text=" +
  text +
  "\n"
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
  let root = @fs.tmpdir(prefix="moonjust-platform")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let justfile = @path.Path(root).join(Path("justfile")).to_string()
  @fs.write_file(
    justfile,
    @utf8.encode("probe:\n  @echo {{invocation_directory()}}\n"),
  )
  let cwd = @env.current_dir().unwrap_or(".")
  let expected = platform_result(official, justfile, cwd)
  let actual = platform_result(candidate, justfile, cwd)
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
    if failures.contains("stdout") {
      @stdio.stderr.write(describe("expected stdout", expected.stdout))
      @stdio.stderr.write(describe("actual stdout", actual.stdout))
    }
    if failures.contains("stderr") {
      @stdio.stderr.write(describe("expected stderr", expected.stderr))
      @stdio.stderr.write(describe("actual stderr", actual.stderr))
    }
    @sys.exit(1)
    return
  }
  @stdio.stdout.write("MoonJust platform differential passed.\n")
}
