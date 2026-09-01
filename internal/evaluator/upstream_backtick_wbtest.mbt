///|
fn backtick_failure_code(command : String, code : Int) -> Int? {
  let cwd = try! @path.PathValue::new("/workspace", @path.Unix)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(@host.OperatingSystem::Linux, "test", @path.Unix),
  )
  let expected = try! @host.CommandSpec::new("sh", ["-cu", command])
  expected.set_cwd(cwd)
  expected.set_inherit_stdin(true)
  expected.set_stdout(@host.Capture)
  expected.set_stderr(@host.Inherit)
  host.expect_process(expected, @host.ProcessResult::new(code, b"", b""))
  try
    ignore(
      evaluate_backtick_with_shell(
        host,
        command,
        EvaluationContext::new(cwd~),
        EffectShell::new("sh", ["-cu"]),
        @source.Span::origin(@source.SourceId::new(969)),
      ),
    )
  catch {
    BacktickFailure(code~, ..) => Some(code)
    _ => None
  } noraise {
    _ => None
  }
}

///|
test "upstream evaluator::tests::backtick_code" {
  assert_eq(backtick_failure_code("f() { return 100; }; f", 100), Some(100))
}

///|
test "upstream evaluator::tests::export_assignment_backtick" {
  assert_eq(backtick_failure_code("echo $exported_variable", 1), Some(1))
}

///|
test "upstream backticks::backtick_with_powershell" {
  assert_false(shell_takes_name("powershell"))
  assert_false(shell_takes_name("powershell.exe"))
  let shell = EffectShell::new("powershell.exe", ["-NoLogo", "-Command"])
  assert_eq(shell.program(), "powershell.exe")
  assert_eq(shell.arguments(), ["-NoLogo", "-Command"])
}
