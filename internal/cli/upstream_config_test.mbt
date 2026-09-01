///|
fn upstream_cli(args : Array[String]) -> CliArguments raise CliParseError {
  parse_arguments(args, Map([]))
}

///|
fn expect_upstream_cli_error(args : Array[String]) -> Bool {
  try upstream_cli(args) catch {
    Invalid(message) => !message.is_empty()
    Config(message) => !message.is_empty()
    Unsupported(message) => !message.is_empty()
  } noraise {
    _ => false
  }
}

///|
test "upstream config::tests::arguments" {
  let parsed = try! upstream_cli(["foo", "bar"])
  assert_eq(parsed.command(), RunCommand)
  assert_eq(parsed.positional(), ["foo", "bar"])
}

///|
test "upstream config::tests::color_default" {
  assert_eq(try! upstream_cli([]).value("color"), Some("auto"))
}

///|
test "upstream config::tests::color_always" {
  assert_eq(
    try! upstream_cli(["--color", "always"]).value("color"),
    Some("always"),
  )
}

///|
test "upstream config::tests::color_auto" {
  assert_eq(try! upstream_cli(["--color", "auto"]).value("color"), Some("auto"))
}

///|
test "upstream config::tests::color_never" {
  assert_eq(
    try! upstream_cli(["--color", "never"]).value("color"),
    Some("never"),
  )
}

///|
test "upstream config::tests::dry_run_default" {
  let parsed = try! upstream_cli([])
  assert_true(!parsed.flag("dry-run"))
}

///|
test "upstream config::tests::dry_run_long" {
  assert_true(try! upstream_cli(["--dry-run"]).flag("dry-run"))
}

///|
test "upstream config::tests::dry_run_short" {
  assert_true(try! upstream_cli(["-n"]).flag("dry-run"))
}

///|
test "upstream config::tests::quiet_default" {
  let parsed = try! upstream_cli([])
  assert_true(!parsed.flag("quiet"))
}

///|
test "upstream config::tests::quiet_long" {
  assert_true(try! upstream_cli(["--quiet"]).flag("quiet"))
}

///|
test "upstream config::tests::quiet_short" {
  assert_true(try! upstream_cli(["-q"]).flag("quiet"))
}

///|
test "upstream config::tests::no_cache" {
  assert_true(try! upstream_cli(["--no-cache"]).flag("no-cache"))
}

///|
test "upstream config::tests::no_dependencies" {
  assert_true(try! upstream_cli(["--no-dependencies"]).flag("no-deps"))
}

///|
test "upstream config::tests::no_deps" {
  assert_true(try! upstream_cli(["--no-deps"]).flag("no-deps"))
}

///|
test "upstream config::tests::fmt_arguments" {
  assert_eq(try! upstream_cli(["--fmt"]).command(), FormatCommand)
}

///|
test "upstream config::tests::fmt_alias" {
  assert_eq(try! upstream_cli(["--format"]).command(), FormatCommand)
}

///|
test "upstream config::tests::init_arguments" {
  assert_eq(try! upstream_cli(["--init"]).command(), InitCommand)
}

///|
test "upstream config::tests::init_alias" {
  assert_eq(try! upstream_cli(["--initialize"]).command(), InitCommand)
}

///|
test "upstream config::tests::dump_arguments" {
  assert_eq(try! upstream_cli(["--dump"]).command(), DumpCommand)
}

///|
test "upstream config::tests::edit_arguments" {
  assert_eq(try! upstream_cli(["--edit"]).command(), EditCommand)
}

///|
test "upstream config::tests::overrides" {
  let parsed = try! upstream_cli(["foo=bar", "build"])
  assert_eq(parsed.positional(), ["build"])
  assert_eq(parsed.variable_overrides(), [("foo", "bar")])
}

///|
test "upstream config::tests::overrides_empty" {
  let parsed = try! upstream_cli(["build"])
  assert_true(parsed.variable_overrides().is_empty())
}

///|
test "upstream config::tests::set_default" {
  assert_true((try! upstream_cli([])).variable_overrides().is_empty())
}

///|
test "upstream config::tests::set_empty" {
  let parsed = try! upstream_cli(["--set", "foo", ""])
  assert_eq(parsed.variable_overrides(), [("foo", "")])
}

///|
test "upstream config::tests::set_one" {
  let parsed = try! upstream_cli(["--set", "foo", "bar"])
  assert_eq(parsed.variable_overrides(), [("foo", "bar")])
}

///|
test "upstream config::tests::set_override" {
  let parsed = try! upstream_cli(["--set", "foo", "bar", "--set", "foo", "baz"])
  assert_eq(parsed.variable_overrides(), [("foo", "bar"), ("foo", "baz")])
}

///|
test "upstream config::tests::overrides_override_sets" {
  let parsed = try! upstream_cli([
    "--set", "foo", "0", "--set", "bar", "1", "foo=bar", "bar=baz",
  ])
  let effective : Map[String, String] = Map([])
  for entry in parsed.variable_overrides() {
    effective[entry.0] = entry.1
  }
  assert_eq([effective["foo"], effective["bar"]], ["bar", "baz"])
  assert_true(parsed.positional().is_empty())
}

///|
test "upstream config::tests::set_two" {
  let parsed = try! upstream_cli(["--set", "foo", "bar", "--set", "bar", "baz"])
  assert_eq(parsed.variable_overrides(), [("foo", "bar"), ("bar", "baz")])
}

///|
test "upstream config::tests::shell_args_default" {
  assert_true((try! upstream_cli([])).shell_arguments() is None)
}

///|
test "upstream config::tests::shell_args_clear" {
  assert_eq(
    (try! upstream_cli(["--clear-shell-args"])).shell_arguments(),
    Some([]),
  )
}

///|
test "upstream config::tests::shell_args_set" {
  assert_eq(
    (try! upstream_cli(["--shell-arg", "hello"])).shell_arguments(),
    Some(["hello"]),
  )
}

///|
test "upstream config::tests::shell_args_set_multiple" {
  assert_eq(
    (try! upstream_cli(["--shell-arg", "foo", "--shell-arg", "bar"])).shell_arguments(),
    Some(["foo", "bar"]),
  )
}

///|
test "upstream config::tests::shell_args_set_and_clear" {
  assert_eq(
    (try! upstream_cli(["--shell-arg", "bar", "--clear-shell-args"])).shell_arguments(),
    Some([]),
  )
}

///|
test "upstream config::tests::shell_args_clear_and_set" {
  assert_eq(
    (try! upstream_cli(["--clear-shell-args", "--shell-arg", "bar"])).shell_arguments(),
    Some(["bar"]),
  )
}

///|
test "upstream config::tests::shell_args_set_hyphen" {
  assert_eq(
    (try! upstream_cli(["--shell-arg", "--foo"])).shell_arguments(),
    Some(["--foo"]),
  )
}

///|
test "upstream config::tests::shell_default" {
  assert_true((try! upstream_cli([])).value("shell") is None)
}

///|
test "upstream config::tests::shell_set" {
  assert_eq(
    (try! upstream_cli(["--shell", "tclsh"])).value("shell"),
    Some("tclsh"),
  )
}

///|
test "upstream config::tests::subcommand_default" {
  assert_eq((try! upstream_cli([])).command(), RunCommand)
}

///|
test "upstream config::tests::subcommand_dump" {
  assert_eq((try! upstream_cli(["--dump"])).command(), DumpCommand)
}

///|
test "upstream config::tests::subcommand_edit" {
  assert_eq((try! upstream_cli(["--edit"])).command(), EditCommand)
}

///|
test "upstream config::tests::subcommand_evaluate" {
  assert_eq((try! upstream_cli(["--evaluate"])).command(), EvaluateCommand)
}

///|
test "upstream config::tests::subcommand_json" {
  assert_eq((try! upstream_cli(["--json"])).command(), JsonCommand)
}

///|
test "upstream config::tests::subcommand_list_long" {
  assert_eq((try! upstream_cli(["--list"])).command(), ListCommand)
}

///|
test "upstream config::tests::subcommand_list_short" {
  assert_eq((try! upstream_cli(["-l"])).command(), ListCommand)
}

///|
test "upstream config::tests::subcommand_show_long" {
  assert_eq((try! upstream_cli(["--show", "foo"])).command(), ShowCommand)
}

///|
test "upstream config::tests::subcommand_show_short" {
  assert_eq((try! upstream_cli(["-s", "foo"])).command(), ShowCommand)
}

///|
test "upstream config::tests::subcommand_summary" {
  assert_eq((try! upstream_cli(["--summary"])).command(), SummaryCommand)
}

///|
test "upstream config::tests::unsorted_default" {
  assert_true(!(try! upstream_cli([])).flag("unsorted"))
}

///|
test "upstream config::tests::unsorted_long" {
  assert_true((try! upstream_cli(["--unsorted"])).flag("unsorted"))
}

///|
test "upstream config::tests::unsorted_short" {
  assert_true((try! upstream_cli(["-u"])).flag("unsorted"))
}

///|
test "upstream config::tests::verbosity_default" {
  assert_eq((try! upstream_cli([])).count("verbose"), 0)
}

///|
test "upstream config::tests::verbosity_long" {
  assert_eq((try! upstream_cli(["--verbose"])).count("verbose"), 1)
}

///|
test "upstream config::tests::verbosity_loquacious" {
  assert_eq((try! upstream_cli(["-vv"])).count("verbose"), 2)
}

///|
test "upstream config::tests::verbosity_grandiloquent" {
  assert_eq((try! upstream_cli(["-vvv"])).count("verbose"), 3)
}

///|
test "upstream config::tests::verbosity_great_grandiloquent" {
  assert_eq((try! upstream_cli(["-vvvv"])).count("verbose"), 4)
}

///|
test "upstream config::tests::summary_arguments" {
  let parsed = try! upstream_cli(["--summary", "foo"])
  assert_eq(parsed.command(), SummaryCommand)
  assert_eq(parsed.positional(), ["foo"])
}

///|
test "upstream config::tests::subcommand_variables" {
  assert_eq((try! upstream_cli(["--variables"])).command(), VariablesCommand)
}

///|
test "upstream config::tests::subcommand_usage_search_directory" {
  let parsed = try! upstream_cli(["--usage", "child"])
  assert_eq(parsed.command(), UsageCommand)
  assert_eq(parsed.positional(), ["child"])
}

///|
test "upstream config::tests::subcommand_evaluate_overrides" {
  let parsed = try! upstream_cli(["--evaluate", "x=y"])
  assert_eq(parsed.command(), EvaluateCommand)
  assert_eq(parsed.variable_overrides(), [("x", "y")])
}

///|
test "upstream config::tests::subcommand_evaluate_overrides_with_argument" {
  let parsed = try! upstream_cli(["--evaluate", "x=y", "foo"])
  assert_eq(parsed.command(), EvaluateCommand)
  assert_eq(parsed.variable_overrides(), [("x", "y")])
  assert_eq(parsed.positional(), ["foo"])
}

///|
test "upstream config::tests::subcommand_list_arguments" {
  let parsed = try! upstream_cli(["--list", "bar"])
  assert_eq(parsed.command(), ListCommand)
  assert_eq(parsed.positional(), ["bar"])
}

///|
test "upstream config::tests::subcommand_show_multiple_args" {
  let parsed = try! upstream_cli(["--show", "foo", "bar"])
  assert_eq(parsed.command(), ShowCommand)
  assert_eq(parsed.positional(), ["foo", "bar"])
}

///|
test "upstream config::tests::color_bad_value" {
  assert_true(expect_upstream_cli_error(["--color", "foo"]))
}

///|
test "upstream config::tests::set_bad" {
  assert_true(expect_upstream_cli_error(["--set", "foo"]))
}

///|
test "upstream config::tests::shell_args_set_multiple_and_clear" {
  assert_eq(
    (try! upstream_cli([
      "--shell-arg", "bar", "--shell-arg", "baz", "--clear-shell-args",
    ])).shell_arguments(),
    Some([]),
  )
}

///|
test "upstream config::tests::shell_args_set_word" {
  assert_eq(
    (try! upstream_cli(["--shell-arg", "foo"])).shell_arguments(),
    Some(["foo"]),
  )
}

///|
test "upstream config::tests::subcommand_conflict_dump" {
  assert_true(expect_upstream_cli_error(["--list", "--dump"]))
}

///|
test "upstream config::tests::search_config_justfile_long" {
  let parsed = try! upstream_cli(["--justfile", "foo"])
  assert_eq(parsed.value("justfile"), Some("foo"))
}

///|
test "upstream config::tests::search_config_justfile_short" {
  let parsed = try! upstream_cli(["-f", "foo"])
  assert_eq(parsed.value("justfile"), Some("foo"))
}

///|
test "upstream config::tests::changelog_arguments" {
  assert_eq(try! upstream_cli(["--changelog"]).command(), ChangelogCommand)
}

///|
test "upstream config::tests::dry_run_quiet" {
  assert_true(expect_upstream_cli_error(["--dry-run", "--quiet"]))
}

///|
test "upstream config::tests::subcommand_conflict_variables" {
  assert_true(expect_upstream_cli_error(["--variables", "--list"]))
}

///|
test "upstream config::tests::subcommand_overrides_and_arguments" {
  assert_true(expect_upstream_cli_error(["--summary", "bar=baz", "bar"]))
}

///|
test "upstream config::tests::summary_overrides" {
  assert_true(expect_upstream_cli_error(["--summary", "bar=baz"]))
}

///|
test "upstream config::tests::dotenv_both_filename_and_path" {
  assert_true(
    expect_upstream_cli_error([
      "--dotenv-filename", "foo", "--dotenv-path", "bar",
    ]),
  )
}

///|
test "upstream config::tests::default_config" {
  let parsed = try! upstream_cli([])
  assert_eq(parsed.command(), RunCommand)
  assert_eq(parsed.value("color"), Some("auto"))
  assert_true(!parsed.flag("dry-run"))
}

///|
test "upstream config::tests::default_config_matches_parsed_config" {
  let parsed = try! upstream_cli([])
  assert_eq(parsed.values("list-heading"), ["Available recipes:\n"])
  assert_eq(parsed.values("list-prefix"), ["    "])
}

///|
test "upstream config::tests::subcommand_conflict_changelog" {
  assert_true(expect_upstream_cli_error(["--changelog", "--list"]))
}

///|
test "upstream config::tests::subcommand_conflict_choose" {
  assert_true(expect_upstream_cli_error(["--choose", "--list"]))
}

///|
test "upstream config::tests::subcommand_conflict_completions" {
  assert_true(expect_upstream_cli_error(["--list", "--completions"]))
}

///|
test "upstream config::tests::subcommand_conflict_evaluate" {
  assert_true(expect_upstream_cli_error(["--evaluate", "--list"]))
}

///|
test "upstream config::tests::subcommand_conflict_fmt" {
  assert_true(expect_upstream_cli_error(["--fmt", "--list"]))
}

///|
test "upstream config::tests::subcommand_conflict_init" {
  assert_true(expect_upstream_cli_error(["--init", "--list"]))
}

///|
test "upstream config::tests::subcommand_conflict_show" {
  assert_true(expect_upstream_cli_error(["--show", "foo", "--list"]))
}

///|
test "upstream config::tests::subcommand_conflict_summary" {
  assert_true(expect_upstream_cli_error(["--summary", "--list"]))
}
