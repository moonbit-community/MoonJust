///|
test "global option aliases and highlight switches are opaque after recipe boundary" {
  let args = [
    "say", "--format", "--highlight", "--no-highlight", "--initialize",
  ]
  for prefix in [[], ["-f", "justfile"], ["--"], ["-f", "justfile", "--"]] {
    let parsed = try! @cli.parse_arguments([..prefix, ..args], Map([]))
    assert_eq(parsed.positional(), args[:])
  }
  let external = try! @cli.parse_arguments(
    ["--command", "echo", "--format", "--set", "x", "y"],
    Map([]),
  )
  assert_eq(external.positional(), ["echo", "--format", "--set", "x", "y"])
}

///|
test "cygpath selects the CLI value before the environment and default" {
  let defaults = try! @cli.parse_arguments(
    ["-f", "justfile", "--summary"],
    Map([]),
  )
  assert_eq(defaults.value("cygpath"), Some("cygpath"))
  let env = { "JUST_CYGPATH": "from-env" }
  for
    (args, expected) in [
      (["--summary"], "from-env"),
      (["--cygpath", "from-cli", "--summary"], "from-cli"),
    ] {
    let parsed = try! @cli.parse_arguments(args, env)
    assert_eq(parsed.value("cygpath"), Some(expected))
  }
}

///|
test "attached global values and short clusters end before opaque recipe argv" {
  let args = ["say", "--", "--jobs", "0", "--cygpath=raw", "--init", "x=y"]
  for prefix in [["-vqfjustfile"], ["-v", "-q", "--justfile=justfile"]] {
    let parsed = try! @cli.parse_arguments([..prefix, ..args], Map([]))
    assert_eq(parsed.value("justfile"), Some("justfile"))
    assert_eq(parsed.count("verbose"), 1)
    assert_true(parsed.flag("quiet"))
    assert_eq(parsed.jobs(), None)
    assert_eq(parsed.positional(), args[:])
  }
}

///|
test "jobs are typed once with argv before environment and absence preserved" {
  let env = { "JUST_JOBS": "5" }
  assert_eq((try! @cli.parse_arguments(["--summary"], Map([]))).jobs(), None)
  assert_eq((try! @cli.parse_arguments([], env)).jobs(), Some(5))
  let parsed = try! @cli.parse_arguments(["--jobs=2"], env)
  assert_eq(parsed.with_run_positionals(["recipe"]).jobs(), Some(2))
  for value in ["0", "not-a-number", "1_0", "-1", "0x10", "2147483648"] {
    for
      (args, vars) in [
        (["--jobs", value], Map([])),
        ([], { "JUST_JOBS": value }),
      ] {
      try @cli.parse_arguments(args, vars) catch {
        Invalid(message) =>
          assert_true(
            message.has_prefix(
              "error: invalid value '\{value}' for '--jobs <N>'",
            ),
          )
        error => fail("unexpected CLI error: \{Repr(error)}")
      } noraise {
        _ => fail("accepted invalid jobs: \{value}")
      }
    }
  }
}

///|
test "cygpath missing its value is a usage error even with an environment default" {
  try
    @cli.parse_arguments(["--cygpath"], { "JUST_CYGPATH": "from-env" })
  catch {
    Invalid(message) => assert_true(message.contains("--cygpath"), msg=message)
    error => fail("unexpected CLI error: \{Repr(error)}")
  } noraise {
    _ => fail("accepted --cygpath without a value")
  }
}

///|
test "only global help flags bypass invalid environment settings" {
  let env = { "JUST_QUIET": "invalid" }
  assert_true((try! @cli.parse_arguments(["-vh"], env)).flag("help"))
  for argv in [["say", "--help"], ["--", "--help"], ["--command", "--help"]] {
    try @cli.parse_arguments(argv, env) catch {
      Invalid(message) => assert_true(message.contains("invalid boolean value"))
      error => fail("unexpected CLI error: \{Repr(error)}")
    } noraise {
      _ => fail("positional --help suppressed a configuration error")
    }
  }
}

///|
test "global options can be interleaved with query paths" {
  let parsed = try! @cli.parse_arguments(
    ["--show", "tools", "--color=never", "build"],
    Map([]),
  )
  assert_eq(parsed.command(), ShowCommand)
  assert_eq(parsed.positional(), ["tools", "build"])
  assert_eq(parsed.value("color"), Some("never"))
}

///|
test "configuration errors report effective overrides in module order, followed by raw arguments" {
  let error = upstream_cli_error([
    "--summary", "--set", "z", "old", "a::n::m=1", "a::x=2", "z=3", "recipe", "next=value",
  ])
  assert_eq(
    error,
    Config(
      "error: `--summary` used with unexpected overrides: `z=3`, `a::x=2`, and `a::n::m=1`; and arguments: `recipe` and `next=value`",
    ),
  )
}
