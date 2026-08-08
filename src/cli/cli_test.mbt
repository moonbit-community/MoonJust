///|
fn diagnostic_fixture(
  code : String,
  message : String,
) -> (@source.SourceMap, @diagnostic.Diagnostic) raise {
  let sources = @source.SourceMap::new()
  let id = @source.SourceId::new(1)
  sources.add(@source.Source::from_text(id, "justfile", "build:\n"))
  let diagnostic = @diagnostic.Diagnostic::new(
    code,
    Error,
    message,
    @source.Span::new(id, 0, 5),
    "here",
  )
  (sources, diagnostic)
}

///|
fn failure_response(
  kind : @cli.FailureKind,
  code : String,
  message : String,
) -> @cli.ApplicationResponse raise {
  let (sources, diagnostic) = diagnostic_fixture(code, message)
  let failure = @cli.ApplicationFailure::new(kind, diagnostic)
  @cli.ApplicationResponse::from_failure(failure, sources)
}

///|
test "usage failures render to stderr and exit with two" {
  let response = failure_response(Usage, "MJ-CLI-0001", "unknown option")
  assert_eq(response.exit_code(), 2)
  assert_true(response.stdout().is_empty())
  let stderr = try! @utf8.decode(response.stderr())
  assert_eq(
    stderr, "error[MJ-CLI-0001]: unknown option\n --> justfile:1:1\n  |\n1 | build:\n  | ^^^^^ here\n",
  )
  assert_false(stderr.contains("\u{001b}"))
}

///|
test "compile and capability failures use generic failure status" {
  let compile = failure_response(Compile, "MJ-COMPILE-0001", "duplicate recipe")
  let capability = failure_response(
    Capability,
    "MJ-CAP-0001",
    "process capability unavailable",
  )
  assert_eq(compile.exit_code(), 1)
  assert_eq(capability.exit_code(), 1)
  assert_true(
    (try! @utf8.decode(capability.stderr())).contains(
      "process capability unavailable",
    ),
  )
}

///|
test "recipe and signal failures preserve upstream exit semantics" {
  let recipe = failure_response(
    RecipeExit(42),
    "MJ-EXEC-0001",
    "recipe failed with exit code 42",
  )
  let signal = failure_response(
    SignalExit(15),
    "MJ-EXEC-0002",
    "recipe was terminated by signal 15",
  )
  assert_eq(recipe.exit_code(), 42)
  assert_eq(signal.exit_code(), 143)
}

///|
test "invalid external status values cannot enter an application response" {
  let (_, diagnostic) = diagnostic_fixture("MJ-EXEC-0003", "bad status")
  try @cli.ApplicationFailure::new(RecipeExit(0), diagnostic) catch {
    InvalidRecipeExitCode(0) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid recipe status")
  }
  try @cli.ApplicationFailure::new(SignalExit(128), diagnostic) catch {
    InvalidSignalNumber(128) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid signal number")
  }
  assert_eq(@cli.ApplicationResponse::new(b"", b"", 300).exit_code(), 300)
}

///|
test "application requests snapshot mutable argument arrays" {
  let arguments = ["build"]
  let request = @cli.ApplicationRequest::run(Search, arguments)
  arguments.push("release")
  match request {
    Run(Search, captured) => {
      assert_eq(captured.length(), 1)
      assert_eq(captured[0], "build")
    }
    _ => fail("expected run request")
  }
  assert_eq(request.arguments().unwrap().length(), 1)
  let path = @path.PathValue::new("justfile", Unix)
  assert_eq(@cli.Check(File(path)), Check(File(path)))
  assert_eq(@cli.Format(Stdin, check_only=true), Format(Stdin, check_only=true))
  assert_eq(@cli.Query(Search, List), Query(Search, List))
}

///|
test "successful responses preserve arbitrary byte streams" {
  let response = @cli.ApplicationResponse::success(
    stdout=b"ok\x00",
    stderr=b"warning\xff",
  )
  assert_eq(response.exit_code(), 0)
  assert_eq(response.stdout(), b"ok\x00")
  assert_eq(response.stderr(), b"warning\xff")
}

///|
test "argparse composition preserves query flags and values" {
  let parsed = @cli.parse_arguments(["--list", "--group", "ci", "build"], {})
  assert_eq(parsed.command(), ListCommand)
  assert_eq(parsed.value("group"), Some("ci"))
  assert_eq(parsed.positional(), ["build"])
  assert_true(parsed.flag("list"))
  let hyphen_value = @cli.parse_arguments(["--list", "--list-prefix", "- "], {})
  assert_eq(hyphen_value.value("list-prefix"), Some("- "))
}

///|
test "argparse composition enforces command relationships" {
  try @cli.parse_arguments(["--check"], {}) catch {
    Invalid(message) => assert_true(message.contains("required argument"))
    Unsupported(_) => fail("expected argparse relationship failure")
  } noraise {
    _ => fail("expected check to require fmt")
  }
  let dry_run = @cli.parse_arguments(["--fmt", "--dry-run"], {})
  assert_eq(dry_run.command(), FormatCommand)
  assert_true(dry_run.flag("dry-run"))
}

///|
test "argparse composition rejects unknown options without side effects" {
  try @cli.parse_arguments(["--definitely-unknown"], {}) catch {
    Invalid(_) => fail("unknown options should be classified as unsupported")
    Unsupported(name) => assert_eq(name, "--definitely-unknown")
  } noraise {
    _ => fail("expected unknown option failure")
  }
}

///|
test "recipe options remain positional after invocation begins" {
  let parsed = @cli.parse_arguments(
    ["build", "--target", "release", "-abc", "--", "--literal"],
    {},
  )
  assert_eq(parsed.command(), RunCommand)
  assert_eq(parsed.positional(), [
    "build", "--target", "release", "-abc", "--", "--literal",
  ])
}

///|
test "recipe options may collide with global option names" {
  let parsed = @cli.parse_arguments(
    ["--justfile", "custom.just", "build", "--quiet", "--list"],
    {},
  )
  assert_eq(parsed.command(), RunCommand)
  assert_false(parsed.flag("quiet"))
  assert_false(parsed.flag("list"))
  assert_eq(parsed.value("justfile"), Some("custom.just"))
  assert_eq(parsed.positional(), ["build", "--quiet", "--list"])
}

///|
test "command modes continue accepting global options after their argument" {
  let parsed = @cli.parse_arguments(
    ["--evaluate", "value", "--justfile", "custom.just"],
    {},
  )
  assert_eq(parsed.command(), EvaluateCommand)
  assert_eq(parsed.positional(), ["value"])
  assert_eq(parsed.value("justfile"), Some("custom.just"))
}

///|
test "working directory requires justfile and remains a global value" {
  let parsed = try! @cli.parse_arguments(
    ["--justfile", "config/justfile", "-d", "run", "build"],
    {},
  )
  assert_eq(parsed.value("justfile"), Some("config/justfile"))
  assert_eq(parsed.value("working-directory"), Some("run"))
  assert_eq(parsed.positional(), ["build"])
  try @cli.parse_arguments(["--working-directory", "run", "build"], {}) catch {
    Invalid(message) => assert_true(message.contains("required argument"))
    error => fail("unexpected working-directory error: \{Repr(error)}")
  } noraise {
    _ => fail("expected working-directory to require justfile")
  }
}

///|
test "query format choices are validated and ignored options are unsupported" {
  let unstable = @cli.parse_arguments(["--unstable", "--json"], {})
  assert_eq(unstable.command(), JsonCommand)
  assert_true(unstable.flag("unstable"))
  for
    arguments in [
      ["--dump", "--dump-format", "yaml"],
      ["--evaluate", "--evaluate-format", "fish"],
      ["--list", "--alias-style", "center"],
    ] {
    try @cli.parse_arguments(arguments, {}) catch {
      Invalid(message) => assert_true(message.contains("invalid value"))
      error => fail("unexpected choice error: \{Repr(error)}")
    } noraise {
      _ => fail("expected invalid query format")
    }
  }
  for
    arguments in [
      ["--list", "--list-submodules"],
      ["--default-list"],
      ["--dump", "--indentation", "  "],
    ] {
    try @cli.parse_arguments(arguments, {}) catch {
      Unsupported(_) => ()
      error => fail("unexpected unsupported error: \{Repr(error)}")
    } noraise {
      _ => fail("expected unsupported option")
    }
  }
}

///|
test "dotenv options append values and enforce upstream conflicts" {
  let parsed = try! parse_arguments(
    ["--dotenv-path", "one.env", "-E", "two.env"],
    {},
  )
  assert_eq(parsed.values("dotenv-path"), ["one.env", "two.env"])
  let filenames = try! parse_arguments(
    ["-F", ".env.one", "--dotenv-filename=.env.two"],
    {},
  )
  assert_eq(filenames.values("dotenv-filename"), [".env.one", ".env.two"])
  for
    arguments in [
      ["--dotenv-command", "true", "--no-dotenv"],
      ["--dotenv-command", "true", "--dotenv-path", ".env"],
      ["--dotenv-filename", ".env", "--dotenv-path", ".other"],
    ] {
    try parse_arguments(arguments, {}) catch {
      Invalid(_) => ()
      error => fail("unexpected dotenv CLI error: \{Repr(error)}")
    } noraise {
      _ => fail("expected dotenv CLI conflict")
    }
  }
}
