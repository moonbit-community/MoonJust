///|
#cfg(not(platform="windows"))
async test "streamed process output enforces the capture boundary" {
  let exact = try! @host.CommandSpec::new("/bin/sh", [
    "-c", "head -c 4096 /dev/zero",
  ])
  exact.set_stdout(Capture)
  exact.set_stderr(Capture)
  let result = try! run_process_with_output_limit(exact, 4096)
  assert_eq(result.termination(), Exited(0))
  assert_eq(result.stdout().length(), 4096)

  let overflow = try! @host.CommandSpec::new("/bin/sh", [
    "-c", "head -c 4097 /dev/zero",
  ])
  overflow.set_stdout(Capture)
  overflow.set_stderr(Capture)
  try run_process_with_output_limit(overflow, 4096) catch {
    InvalidInput(message) =>
      assert_eq(
        message, "process captured output exceeded the 4096-byte per-stream limit",
      )
    error => fail("unexpected output limit error: \{Repr(error)}")
  } noraise {
    _ => fail("expected process output limit failure")
  }
}

///|
#cfg(platform="windows")
fn windows_output_command(byte_count : Int) -> @host.CommandSpec {
  try! @host.CommandSpec::new("powershell.exe", [
    "-NoLogo",
    "-NoProfile",
    "-NonInteractive",
    "-Command",
    "[Console]::Out.Write(('0' * \{byte_count}) -join '')",
  ])
}

///|
#cfg(platform="windows")
async test "Windows streamed process output enforces the capture boundary" {
  let exact = windows_output_command(4096)
  exact.set_stdout(Capture)
  exact.set_stderr(Capture)
  let result = try! run_process_with_output_limit(exact, 4096)
  assert_eq(result.termination(), Exited(0))
  assert_eq(result.stdout().length(), 4096)

  let overflow = windows_output_command(4097)
  overflow.set_stdout(Capture)
  overflow.set_stderr(Capture)
  try run_process_with_output_limit(overflow, 4096) catch {
    InvalidInput(message) =>
      assert_eq(
        message, "process captured output exceeded the 4096-byte per-stream limit",
      )
    error => fail("unexpected output limit error: \{Repr(error)}")
  } noraise {
    _ => fail("expected process output limit failure")
  }
}
