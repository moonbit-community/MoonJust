///|
test "Windows executable candidates follow PATH and PATHEXT order" {
  assert_eq(
    windows_program_candidates(
      "sh", "C:\\Git\\bin;D:\\Tools", ".COM;.EXE;.BAT;.CMD",
    ),
    [
      "sh.COM", "sh.EXE", "sh.BAT", "sh.CMD", "C:\\Git\\bin\\sh.COM", "C:\\Git\\bin\\sh.EXE",
      "C:\\Git\\bin\\sh.BAT", "C:\\Git\\bin\\sh.CMD", "D:\\Tools\\sh.COM", "D:\\Tools\\sh.EXE",
      "D:\\Tools\\sh.BAT", "D:\\Tools\\sh.CMD",
    ],
  )
}

///|
test "Windows executable candidates preserve explicit paths and extensions" {
  assert_eq(
    windows_program_candidates(
      "C:\\Tools\\runner.exe", "D:\\Ignored", ".EXE;.CMD",
    ),
    ["C:\\Tools\\runner.exe"],
  )
  assert_eq(
    windows_program_candidates("bin\\runner", "D:\\Ignored", "EXE;CMD"),
    [],
  )
}

///|
test "Windows batch programs use cmd without changing arguments" {
  assert_eq(
    windows_batch_command("C:\\Tools\\runner.CMD", ["/C", "echo hi"], true),
    ("cmd.exe", ["/d", "/s", "/c", "C:\\Tools\\runner.CMD", "/C", "echo hi"]),
  )
  assert_eq(
    windows_batch_command("runner.exe", ["one"], true),
    ("runner.exe", ["one"]),
  )
  assert_eq(
    windows_batch_command("runner.cmd", ["one"], false),
    ("runner.cmd", ["one"]),
  )
}

///|
test "Windows batch bodies and undefined variables preserve cmd semantics" {
  assert_eq(
    windows_batch_body("for %x in (a) do echo %x"),
    "for %%x in (a) do echo %%x",
  )
  assert_eq(windows_batch_body("echo %PATH%"), "echo %PATH%")
  assert_eq(
    windows_escape_undefined_variables(
      "echo %MISSING% %KNOWN%",
      [("KNOWN", "1")],
      false,
    ),
    "echo %%MISSING%% %KNOWN%",
  )
  assert_true(windows_environment_contains("known", [("KNOWN", "1")], false))
  assert_false(windows_environment_contains("missing", [], false))
}

///|
test "Windows direct commands and resolution cache keys preserve boundaries" {
  for command in [":", "echo hello", "exit 0", "C:\\tools\\run.exe value"] {
    assert_true(windows_direct_command_safe(command))
  }
  for
    command in [
      "", "echo %PATH%", "echo !VALUE!", "echo one & echo two", "echo \"quoted\"",
      "echo one\ntwo", "tools\\build.cmd",
    ] {
    assert_false(windows_direct_command_safe(command))
  }
  let base = windows_resolution_key(
    "tool", "C:\\work", "C:\\bin", ".EXE;.CMD", "cygpath",
  )
  assert_eq(
    base,
    windows_resolution_key(
      "tool", "C:\\work", "C:\\bin", ".EXE;.CMD", "cygpath",
    ),
  )
  assert_true(
    base !=
    windows_resolution_key(
      "tool", "D:\\work", "C:\\bin", ".EXE;.CMD", "cygpath",
    ),
  )
  assert_true(
    base !=
    windows_resolution_key(
      "tool", "C:\\work", "D:\\bin", ".EXE;.CMD", "cygpath",
    ),
  )
  assert_true(
    windows_shell_mode("cmd.exe", ["/d", "/s", "/c", "echo ok"]) ==
    "cmd-command",
  )
  assert_true(windows_shell_mode("runner.cmd", []) == "batch")
  assert_true(windows_shell_mode("runner.exe", []) == "direct")
}
