///|
fn upstream_setting_undefined(
  text : String,
  expected_name : String,
  start : Int,
) -> Unit raise {
  try
    @semantic.compile_source(
      @source.Source::from_text(@source.SourceId::new(965), "justfile", text),
    )
  catch {
    UndefinedVariable(name~, span~) => {
      assert_eq(name, expected_name)
      assert_eq(span.start_byte(), start)
      assert_eq(span.length(), expected_name.length())
    }
    error => fail("unexpected semantic error: \{Repr(error)}")
  } noraise {
    _ => fail("expected undefined variable")
  }
}

///|
test "upstream settings::undefined_variable_in_script_interpreter_command" {
  upstream_setting_undefined("set script-interpreter := [foo]", "foo", 27)
}

///|
test "upstream settings::undefined_variable_in_shell_command" {
  upstream_setting_undefined("set shell := [foo]", "foo", 14)
}

///|
test "upstream settings::undefined_variable_in_tempdir" {
  upstream_setting_undefined("set tempdir := foo", "foo", 15)
}

///|
test "upstream settings::undefined_variable_in_windows_shell_argument" {
  upstream_setting_undefined("set windows-shell := ['foo', bar]", "bar", 29)
}

///|
test "upstream settings::undefined_variable_in_windows_shell_command" {
  upstream_setting_undefined("set windows-shell := [foo]", "foo", 22)
}
