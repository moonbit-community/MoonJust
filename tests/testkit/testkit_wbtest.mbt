///|
async test "prepared command preserves executable prefix and subject" {
  let command = prepare_command(
    "moonx",
    ["--target", "wasm", "ZSeanYves/MoonJust@0.1.2"],
    subject_path="ZSeanYves/MoonJust@0.1.2",
  )
  assert_eq(command.executable, "moonx")
  assert_eq(command.arguments(["--version"]), [
    "--target", "wasm", "ZSeanYves/MoonJust@0.1.2", "--version",
  ])
  assert_eq(command.subject(), "ZSeanYves/MoonJust@0.1.2")
  assert_true(command.is_wrapped())
}
