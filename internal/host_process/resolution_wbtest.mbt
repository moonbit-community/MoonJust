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
