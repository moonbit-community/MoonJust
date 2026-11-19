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
test "a global option terminates the preceding query path" {
  let parsed = try! @cli.parse_arguments(
    ["--show", "tools", "build", "--color=never"],
    Map([]),
  )
  assert_eq(parsed.command(), ShowCommand)
  assert_eq(parsed.positional(), ["tools", "build"])
  assert_eq(parsed.value("color"), Some("never"))
  assert_cli_usage_error(
    ["--show", "tools", "--color=never", "build"],
    "error: the argument '--show <RECIPE_PATH>...' cannot be used with '[ARGUMENTS]...'",
  )
}

///|
test "release query paths support attached operands and retain recipe and external argument boundaries" {
  for
    (argv, path) in [
      (["--usage"], []),
      (["--usage=tools", "-d", "child"], ["tools"]),
      (["--usage", "tools", "build", "-dchild"], ["tools", "build"]),
    ] {
    let args = try! upstream_cli(argv)
    assert_eq(args.command(), UsageCommand)
    assert_eq(args.positional(), path[:])
  }
  let shown = try! upstream_cli(["-qsbuild"])
  assert_true(shown.flag("quiet"))
  assert_eq(shown.positional(), ["build"])
  let trailing = ["--justfile-name=x,y", "-d", "other", "--usage=tools"]
  for prefix in [["recipe"], ["--command", "exec"], ["--", "recipe"]] {
    let args = try! upstream_cli(["-d.", ..prefix, ..trailing])
    assert_eq(args.value("working-directory"), Some("."))
    assert_true(args.values("justfile-name").is_empty())
    assert_eq(args.positional()[1:], trailing[:])
  }
}

///|
test "release discovery usage errors preserve option order and explicit environment inputs" {
  let footer = "\n\nFor more information, try '--help'."
  for
    (argv, option) in [
      (["-d"], "--working-directory <WORKING_DIRECTORY>"),
      (["-d", "--summary"], "--working-directory <WORKING_DIRECTORY>"),
      (["--justfile-name", "--"], "--justfile-name <NAME>"),
      (["--show", "--help"], "--show <RECIPE_PATH>..."),
    ] {
    assert_eq(
      upstream_cli_error(argv),
      Invalid(
        "error: a value is required for '\{option}' but none was supplied" +
        footer,
      ),
    )
  }
  assert_eq(
    upstream_cli_error(["-d.", "-d", "elsewhere"]),
    Invalid(
      "error: the argument '--working-directory <WORKING_DIRECTORY>' cannot be used multiple times\n\nUsage: just [OPTIONS] [ARGUMENTS]..." +
      footer,
    ),
  )
  for
    (argv, env, reason, usage) in [
      (
        ["--summary", "-g", "-d."],
        { "JUST_COLOR": "never" },
        "'--global-justfile' cannot be used with '--working-directory <WORKING_DIRECTORY>'",
        "--summary --global-justfile --color <COLOR>",
      ),
      (
        ["-d.", "-g", "--summary"],
        Map([]),
        "'--working-directory <WORKING_DIRECTORY>' cannot be used with '--global-justfile'",
        "--working-directory <WORKING_DIRECTORY> --summary",
      ),
      (
        ["--usage", "-v", "a", "-q"],
        { "JUST_COLOR": "never" },
        "'--usage [<PATH>...]' cannot be used with '[ARGUMENTS]...'",
        "--usage [<PATH>...] --verbose... --color <COLOR>",
      ),
    ] {
    try @cli.parse_arguments(argv, env) catch {
      Invalid(message) =>
        assert_eq(
          message,
          "error: the argument " +
          reason +
          "\n\nUsage: just " +
          usage +
          " [ARGUMENTS]..." +
          footer,
        )
      error => fail("unexpected CLI error: \{Repr(error)}")
    } noraise {
      _ => fail("invalid invocation was accepted")
    }
  }
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
