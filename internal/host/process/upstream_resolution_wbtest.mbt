///|
test "upstream resolve::absolute_path_bypasses_path_search" {
  assert_eq(windows_program_candidates("C:\\tmp\\foo.cmd", "C:\\bin", ".CMD"), [
    "C:\\tmp\\foo.cmd",
  ])
}

///|
test "upstream resolve::command_resolved_via_pathext" {
  assert_eq(windows_program_candidates("foo", "C:\\bin", ".CMD"), [
    "foo.CMD", "C:\\bin\\foo.CMD",
  ])
}

///|
test "upstream resolve::existing_extension_skips_pathext" {
  assert_eq(windows_program_candidates("foo.cmd", "C:\\bin", ".EXE"), [
    "foo.cmd", "C:\\bin\\foo.cmd",
  ])
}

///|
test "upstream resolve::path_ordering" {
  assert_eq(windows_program_candidates("foo", "C:\\one;C:\\two", ".CMD"), [
    "foo.CMD", "C:\\one\\foo.CMD", "C:\\two\\foo.CMD",
  ])
}

///|
test "upstream resolve::relative_path_with_directory_bypasses_path_search" {
  assert_eq(windows_program_candidates("sub\\foo.cmd", "C:\\bin", ".CMD"), [
    "sub\\foo.cmd",
  ])
}

///|
test "upstream resolve::script_interpreter_resolved_via_pathext" {
  assert_eq(windows_program_candidates("myinterp", "C:\\bin", ".CMD"), [
    "myinterp.CMD", "C:\\bin\\myinterp.CMD",
  ])
}

///|
test "upstream resolve::shell_resolved_via_pathext" {
  assert_eq(windows_program_candidates("myshell", "C:\\bin", ".CMD"), [
    "myshell.CMD", "C:\\bin\\myshell.CMD",
  ])
}

///|
test "upstream resolve::command_on_custom_path" {
  assert_eq(windows_program_candidates("foo.exe", "/custom", ".EXE"), [
    "foo.exe", "/custom\\foo.exe",
  ])
}

///|
test "upstream resolve::shell_on_custom_path" {
  assert_eq(windows_program_candidates("myshell.exe", "/custom", ".EXE"), [
    "myshell.exe", "/custom\\myshell.exe",
  ])
}
