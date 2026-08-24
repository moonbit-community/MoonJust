///|
fn assert_config_contract(
  args : ArrayView[String],
  flags : ArrayView[(String, Bool)],
  values : ArrayView[(String, String)],
  shell_arguments : Array[String]?,
  positional : ArrayView[String],
  overrides : ArrayView[(String, String)],
) -> Unit raise {
  let parsed = @cli.parse_arguments(args, {})
  assert_eq(parsed.command(), RunCommand)
  for flag in flags {
    assert_eq(parsed.flag(flag.0), flag.1)
  }
  for value in values {
    assert_eq(parsed.value(value.0), Some(value.1))
  }
  assert_eq(parsed.shell_arguments(), shell_arguments)
  assert_eq(parsed.positional(), positional)
  assert_eq(parsed.variable_overrides(), overrides)
}

///|
test "contract JUST-1.57.0-0364 config::tests::arguments" {
  assert_config_contract(["foo", "bar"], [], [], None, ["foo", "bar"], [])
}

///|
test "contract JUST-1.57.0-0366 config::tests::color_always" {
  assert_config_contract(
    ["--color", "always"],
    [],
    [("color", "always")],
    None,
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0367 config::tests::color_auto" {
  assert_config_contract(
    ["--color", "auto"],
    [],
    [("color", "auto")],
    None,
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0370 config::tests::color_never" {
  assert_config_contract(
    ["--color", "never"],
    [],
    [("color", "never")],
    None,
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0379 config::tests::dry_run_long" {
  assert_config_contract(["--dry-run"], [("dry-run", true)], [], None, [], [])
}

///|
test "contract JUST-1.57.0-0381 config::tests::dry_run_short" {
  assert_config_contract(["-n"], [("dry-run", true)], [], None, [], [])
}

///|
test "contract JUST-1.57.0-0387 config::tests::highlight_no" {
  assert_config_contract(
    ["--no-highlight"],
    [("highlight", false), ("no-highlight", true)],
    [],
    None,
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0388 config::tests::highlight_no_yes" {
  assert_config_contract(
    ["--no-highlight", "--highlight"],
    [("highlight", true), ("no-highlight", false)],
    [],
    None,
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0389 config::tests::highlight_no_yes_no" {
  assert_config_contract(
    ["--no-highlight", "--highlight", "--no-highlight"],
    [("highlight", false), ("no-highlight", true)],
    [],
    None,
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0390 config::tests::highlight_yes" {
  assert_config_contract(
    ["--highlight"],
    [("highlight", true), ("no-highlight", false)],
    [],
    None,
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0391 config::tests::highlight_yes_no" {
  assert_config_contract(
    ["--highlight", "--no-highlight"],
    [("highlight", false), ("no-highlight", true)],
    [],
    None,
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0395 config::tests::no_dependencies" {
  assert_config_contract(
    ["--no-dependencies"],
    [("no-deps", true)],
    [],
    None,
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0396 config::tests::no_deps" {
  assert_config_contract(["--no-deps"], [("no-deps", true)], [], None, [], [])
}

///|
test "contract JUST-1.57.0-0397 config::tests::overrides" {
  assert_config_contract(["foo=bar", "bar=baz"], [], [], None, [], [
    ("foo", "bar"),
    ("bar", "baz"),
  ])
}

///|
test "contract JUST-1.57.0-0398 config::tests::overrides_empty" {
  assert_config_contract(["foo=", "bar="], [], [], None, [], [
    ("foo", ""),
    ("bar", ""),
  ])
}

///|
test "contract JUST-1.57.0-0403 config::tests::search_config_default" {
  assert_config_contract([], [], [], None, [], [])
}

///|
test "contract JUST-1.57.0-0404 config::tests::search_config_from_working_directory_and_justfile" {
  assert_config_contract(
    ["--working-directory", "foo", "--justfile", "bar"],
    [],
    [("working-directory", "foo"), ("justfile", "bar")],
    None,
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0405 config::tests::search_config_justfile_long" {
  assert_config_contract(
    ["--justfile", "foo"],
    [],
    [("justfile", "foo")],
    None,
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0406 config::tests::search_config_justfile_short" {
  assert_config_contract(["-f", "foo"], [], [("justfile", "foo")], None, [], [])
}

///|
test "contract JUST-1.57.0-0407 config::tests::search_config_justfile_stdin_long" {
  assert_config_contract(
    ["--justfile", "-"],
    [],
    [("justfile", "-")],
    None,
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0408 config::tests::search_config_justfile_stdin_short" {
  assert_config_contract(["-f", "-"], [], [("justfile", "-")], None, [], [])
}

///|
test "contract JUST-1.57.0-0409 config::tests::search_config_justfile_stdin_with_working_directory" {
  assert_config_contract(
    ["--justfile", "-", "--working-directory", "foo"],
    [],
    [("justfile", "-"), ("working-directory", "foo")],
    None,
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0418 config::tests::set_default" {
  assert_config_contract([], [], [], None, [], [])
}

///|
test "contract JUST-1.57.0-0419 config::tests::set_empty" {
  assert_config_contract(["--set", "foo", ""], [], [], None, [], [("foo", "")])
}

///|
test "contract JUST-1.57.0-0420 config::tests::set_one" {
  assert_config_contract(["--set", "foo", "bar"], [], [], None, [], [
    ("foo", "bar"),
  ])
}

///|
test "contract JUST-1.57.0-0421 config::tests::set_override" {
  assert_config_contract(
    ["--set", "foo", "bar", "--set", "foo", "baz"],
    [],
    [],
    None,
    [],
    [("foo", "bar"), ("foo", "baz")],
  )
}

///|
test "contract JUST-1.57.0-0422 config::tests::set_two" {
  assert_config_contract(
    ["--set", "foo", "bar", "--set", "bar", "baz"],
    [],
    [],
    None,
    [],
    [("foo", "bar"), ("bar", "baz")],
  )
}

///|
test "contract JUST-1.57.0-0423 config::tests::shell_args_clear" {
  assert_config_contract(["--clear-shell-args"], [], [], Some([]), [], [])
}

///|
test "contract JUST-1.57.0-0424 config::tests::shell_args_clear_and_set" {
  assert_config_contract(
    ["--clear-shell-args", "--shell-arg", "bar"],
    [],
    [],
    Some(["bar"]),
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0425 config::tests::shell_args_default" {
  assert_config_contract([], [], [], None, [], [])
}

///|
test "contract JUST-1.57.0-0426 config::tests::shell_args_set" {
  assert_config_contract(
    ["--shell-arg", "hello"],
    [],
    [],
    Some(["hello"]),
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0427 config::tests::shell_args_set_and_clear" {
  assert_config_contract(
    ["--shell-arg", "bar", "--clear-shell-args"],
    [],
    [],
    Some([]),
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0428 config::tests::shell_args_set_hyphen" {
  assert_config_contract(
    ["--shell-arg", "--foo"],
    [],
    [],
    Some(["--foo"]),
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0429 config::tests::shell_args_set_multiple" {
  assert_config_contract(
    ["--shell-arg", "foo", "--shell-arg", "bar"],
    [],
    [],
    Some(["foo", "bar"]),
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0430 config::tests::shell_args_set_multiple_and_clear" {
  assert_config_contract(
    ["--shell-arg", "bar", "--shell-arg", "baz", "--clear-shell-args"],
    [],
    [],
    Some([]),
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0431 config::tests::shell_args_set_word" {
  assert_config_contract(["--shell-arg", "foo"], [], [], Some(["foo"]), [], [])
}

///|
test "contract JUST-1.57.0-0432 config::tests::shell_default" {
  assert_config_contract([], [], [], None, [], [])
}

///|
test "contract JUST-1.57.0-0433 config::tests::shell_set" {
  assert_config_contract(
    ["--shell", "tclsh"],
    [],
    [("shell", "tclsh")],
    None,
    [],
    [],
  )
}

///|
test "contract JUST-1.57.0-0468 config::tests::unsorted_long" {
  assert_config_contract(["--unsorted"], [("unsorted", true)], [], None, [], [])
}

///|
test "contract JUST-1.57.0-0469 config::tests::unsorted_short" {
  assert_config_contract(["-u"], [("unsorted", true)], [], None, [], [])
}
