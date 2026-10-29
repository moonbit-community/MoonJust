///|
test "parse invocation preserves command values and positionals" {
  let parsed = try! @cli.parse_arguments(
    ["--list", "--group", "ci", "build"],
    Map([]),
  )
  assert_eq(parsed.command(), ListCommand)
  assert_eq(parsed.value("group"), Some("ci"))
  assert_eq(parsed.positional(), ["build"])
  assert_true(parsed.flag("list"))
}

///|
test "parse invocation reports invalid command combinations" {
  try @cli.parse_arguments(["--group", "ci"], Map([])) catch {
    Invalid(message) => assert_true(message.contains("--group"))
    error => fail("unexpected parse error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid group option")
  }
}

///|
test "static flags remain parseable without environment" {
  let help = try! @cli.parse_arguments(["--help"], Map([]))
  assert_true(help.flag("help"))
  assert_eq(help.command(), RunCommand)
  let version = try! @cli.parse_arguments(["-V"], Map([]))
  assert_true(version.flag("version"))
}
