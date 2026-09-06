///|
async test "prepared command preserves executable prefix and subject" {
  let command = prepare_command(
    "moonx",
    ["--target", "wasm", "ZSeanYves/MoonJust@0.1.2"],
    subject_path="ZSeanYves/MoonJust@0.1.2",
  )
  assert_true(
    if is_windows_platform() {
      command.executable.to_lower().has_suffix(".exe")
    } else {
      command.executable == "moonx"
    },
  )
  assert_eq(command.arguments(["--version"]), [
    "--target", "wasm", "ZSeanYves/MoonJust@0.1.2", "--version",
  ])
  assert_eq(command.subject(), "ZSeanYves/MoonJust@0.1.2")
  assert_true(command.is_wrapped())
}

///|
async test "bare Windows programs resolve from PATH without application-directory lookup" {
  let root = @fs.tmpdir(prefix="moonjust testkit resolution")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let bin = @path.Path(root).join(Path("bin")).to_string()
  @fs.mkdir(bin, recursive=true)
  let executable = @path.Path(bin).join(Path("moonx.exe")).to_string()
  @fs.write_file(executable, b"test executable"[:])
  let resolved = resolve_windows_program_with_context(
    "moonx",
    bin + "/",
    ".com;.exe;.bat;.cmd",
  )
  assert_eq(resolved, @fs.realpath(executable))
}
