///|
#cfg(not(platform="windows"))
test "signal child registry reports capacity without aborting" {
  for index in 0..<1024 {
    assert_eq(register_signal_child_ffi(-index - 1), 1)
  }
  assert_eq(register_signal_child_ffi(-2048), 0)
  for index in 0..<1024 {
    assert_eq(unregister_signal_child_ffi(-index - 1), 0)
  }
}

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
    ["bin\\runner.EXE", "bin\\runner.CMD"],
  )
}
