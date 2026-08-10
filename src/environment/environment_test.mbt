///|
fn unix_path(value : String) -> @path.PathValue {
  try! @path.PathValue::new(value, Unix)
}

///|
test "dotenv parser matches dotenvy quoting escaping comments and export" {
  let input =
    #|KEY=1
    #|KEY2="two words"
    #|KEY3='literal $KEY'
    #|KEY4=my\ cool\ value
    #|KEY5="line 1
    #|line 2"
    #|export SHELL_LOVER=1
    #|HASH=value#kept # discarded
    #|
  let parsed = try parse_dotenv(input) catch {
    error => fail("unexpected dotenv parse error: \{Repr(error)}")
  } noraise {
    value => value
  }
  assert_eq(parsed.get("KEY"), Some("1"))
  assert_eq(parsed.get("KEY2"), Some("two words"))
  assert_eq(parsed.get("KEY3"), Some("literal $KEY"))
  assert_eq(parsed.get("KEY4"), Some("my cool value"))
  assert_eq(parsed.get("KEY5"), Some("line 1\nline 2"))
  assert_eq(parsed.get("SHELL_LOVER"), Some("1"))
  assert_eq(parsed.get("HASH"), Some("value#kept"))
}

///|
test "dotenv parser matches just from_read_iter BOM rejection" {
  try parse_dotenv("\u{feff}KEY=value") catch {
    Parse(line=1, column=1) => ()
    error => fail("unexpected BOM error: \{Repr(error)}")
  } noraise {
    _ => fail("expected BOM rejection")
  }
}

///|
test "dotenv substitutions prefer ambient environment and retain dotenvy boundaries" {
  let ambient = EnvTable::from_entries([("KEY11", "ambient")][:])
  let input =
    #|KEY1=test_user
    #|KEY1_1=long
    #|KEY11=local
    #|PLAIN=$KEY1_1
    #|BRACED=${KEY1_1}
    #|AMBIENT=${KEY11}
    #|ESCAPED=\$KEY1
    #|STRONG='${KEY1}'
  let parsed = parse_dotenv(input, ambient~)
  assert_eq(parsed.get("PLAIN"), Some("test_user_1"))
  assert_eq(parsed.get("BRACED"), Some("long"))
  assert_eq(parsed.get("AMBIENT"), Some("ambient"))
  assert_eq(parsed.get("ESCAPED"), Some("$KEY1"))
  assert_eq(parsed.get("STRONG"), Some("${KEY1}"))
}

///|
test "dotenv parser errors are structurally redacted" {
  try parse_dotenv("TOKEN=top-secret unquoted") catch {
    error => {
      assert_true(error is Parse(line=1, ..))
      assert_false(error.message().contains("top-secret"))
      assert_false("\{Repr(error)}".contains("top-secret"))
    }
  } noraise {
    _ => fail("expected parse failure")
  }
}

///|
test "dotenv parser handles CRLF and rejects malformed escapes and quotes" {
  let crlf = parse_dotenv("A=one\r\nB='two\r\nlines'\r\nC=three\r\n")
  assert_eq(crlf.get("A"), Some("one"))
  assert_eq(crlf.get("B"), Some("two\r\nlines"))
  assert_eq(crlf.get("C"), Some("three"))
  for input in ["A=bad\\q", "A='unterminated", "A=\"unterminated"] {
    try parse_dotenv(input) catch {
      Parse(_) => ()
      error => fail("unexpected parser hardening error: \{Repr(error)}")
    } noraise {
      _ => fail("expected malformed dotenv rejection")
    }
  }
}

///|
test "dotenv file loading implements path filename precedence and ancestor search" {
  let host = @host.FakeHost::new(
    unix_path("/project/sub"),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  host.put_file(unix_path("/project/.env.first"), b"A=first\nSHARED=first")
  host.put_file(unix_path("/project/.env.second"), b"B=second\nSHARED=second")
  let loaded = load_dotenv_files(
    host,
    unix_path("/project/sub"),
    EnvTable::new(),
    DotenvOptions::new(load=true, lists=true, filenames=[
      ".env.first", ".env.second",
    ]),
  )
  assert_eq(loaded.get("A"), Some("first"))
  assert_eq(loaded.get("B"), Some("second"))
  assert_eq(loaded.get("SHARED"), Some("second"))
  host.put_file(unix_path("/project/sub/explicit.env"), b"SHARED=explicit")
  let explicit = load_dotenv_files(
    host,
    unix_path("/project/sub"),
    EnvTable::new(),
    DotenvOptions::new(load=true, paths=["explicit.env"], filenames=[
      ".env.first",
    ]),
  )
  assert_eq(explicit.get("SHARED"), Some("explicit"))
}

///|
test "dotenv paths merge last-wins and missing paths fall through to filename search" {
  let host = @host.FakeHost::new(
    unix_path("/project/sub"),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  host.put_file(unix_path("/project/sub/one.env"), b"KEY=one\nONE=yes")
  host.put_file(unix_path("/project/sub/two.env"), b"KEY=two\nTWO=yes")
  host.put_file(unix_path("/project/.env"), b"KEY=fallback")
  let paths = load_dotenv_files(
    host,
    unix_path("/project/sub"),
    EnvTable::new(),
    DotenvOptions::new(load=true, lists=true, paths=["one.env", "two.env"]),
  )
  assert_eq(paths.get("KEY"), Some("two"))
  assert_eq(paths.get("ONE"), Some("yes"))
  assert_eq(paths.get("TWO"), Some("yes"))
  let fallback = load_dotenv_files(
    host,
    unix_path("/project/sub"),
    EnvTable::new(),
    DotenvOptions::new(load=true, lists=true, paths=[
      "missing-one", "missing-two",
    ]),
  )
  assert_eq(fallback.get("KEY"), Some("fallback"))
}

///|
test "dotenv filename search stops at the first directory with any hit" {
  let host = @host.FakeHost::new(
    unix_path("/project/sub"),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  host.put_file(unix_path("/project/sub/.env.one"), b"ONE=child")
  host.put_file(unix_path("/project/.env.two"), b"TWO=parent")
  let loaded = load_dotenv_files(
    host,
    unix_path("/project/sub"),
    EnvTable::new(),
    DotenvOptions::new(load=true, lists=true, filenames=[".env.one", ".env.two"]),
  )
  assert_eq(loaded.get("ONE"), Some("child"))
  assert_eq(loaded.get("TWO"), None)
}

///|
test "dotenv override required and list contracts match upstream" {
  let host = @host.FakeHost::new(
    unix_path("/work"),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  host.put_file(unix_path("/work/.env"), b"KEY=dotenv")
  let ambient = EnvTable::from_entries([("KEY", "shell")][:])
  let preserved = load_dotenv_files(
    host,
    unix_path("/work"),
    ambient,
    DotenvOptions::new(load=true),
  )
  assert_eq(preserved.get("KEY"), None)
  let overridden = load_dotenv_files(
    host,
    unix_path("/work"),
    ambient,
    DotenvOptions::new(load=true, override_environment=true),
  )
  assert_eq(overridden.get("KEY"), Some("dotenv"))
  try
    load_dotenv_files(
      host,
      unix_path("/missing"),
      ambient,
      DotenvOptions::new(required=true),
    )
  catch {
    Required => ()
    error => fail("unexpected required error: \{Repr(error)}")
  } noraise {
    _ => fail("expected required failure")
  }
  try
    load_dotenv_files(
      host,
      unix_path("/work"),
      ambient,
      DotenvOptions::new(load=true, paths=["one", "two"]),
    )
  catch {
    ArgumentsRequireLists => ()
    error => fail("unexpected list error: \{Repr(error)}")
  } noraise {
    _ => fail("expected list failure")
  }
}

///|
test "disabled dotenv avoids filesystem access and host failures stay redacted" {
  let host = @host.FakeHost::new(
    unix_path("/work"),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  host.deny(FsRead)
  assert_eq(
    load_dotenv_files(
      host,
      unix_path("/work"),
      EnvTable::new(),
      DotenvOptions::new(),
    ).entries(),
    [],
  )
  try
    ignore(
      load_dotenv_files(
        host,
        unix_path("/work"),
        EnvTable::new(),
        DotenvOptions::new(load=true),
      ),
    )
  catch {
    HostDenied(FsRead) => {
      let error : DotenvError = HostDenied(FsRead)
      assert_eq(error.message(), "environment source access denied")
      assert_eq(error.exit_code(), 1)
    }
    error => fail("unexpected host dotenv error: \{Repr(error)}")
  } noraise {
    _ => fail("expected host capability failure")
  }
}

///|
test "dotenv commands merge in order honor override and skip dry runs" {
  let host = @host.FakeHost::new(
    unix_path("/work"),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let first = try! @host.CommandSpec::new("sh", ["-c", "first"])
  first.set_cwd(unix_path("/work"))
  host.expect_process(
    first,
    @host.ProcessResult::new(0, b"A=one\nKEY=first", b""),
  )
  let second = try! @host.CommandSpec::new("sh", ["-c", "second"])
  second.set_cwd(unix_path("/work"))
  host.expect_process(
    second,
    @host.ProcessResult::new(0, b"B=two\nKEY=second", b""),
  )
  let commands = [
    try! @host.CommandSpec::new("sh", ["-c", "first"]),
    try! @host.CommandSpec::new("sh", ["-c", "second"]),
  ]
  let loaded = load_dotenv_commands(
    host,
    unix_path("/work"),
    EnvTable::new(),
    DotenvOptions::new(commands~),
  )
  assert_eq(loaded.get("A"), Some("one"))
  assert_eq(loaded.get("B"), Some("two"))
  assert_eq(loaded.get("KEY"), Some("second"))
  assert_eq(host.pending_process_expectations(), 0)
  let dry = load_dotenv_commands(
    host,
    unix_path("/work"),
    EnvTable::new(),
    DotenvOptions::new(dry_run=true, commands=[
      try! @host.CommandSpec::new("sh", ["-c", "never"]),
    ]),
  )
  assert_eq(dry.entries(), [])
}

///|
test "dotenv command honors ambient precedence and propagates redacted status" {
  let host = @host.FakeHost::new(
    unix_path("/work"),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let expected = try! @host.CommandSpec::new("sh", ["-c", "emit"])
  expected.set_cwd(unix_path("/work"))
  host.expect_process(
    expected,
    @host.ProcessResult::new(0, b"TOKEN=dotenv", b""),
  )
  let ambient = EnvTable::from_entries([("TOKEN", "shell-secret")][:])
  let preserved = load_dotenv_commands(
    host,
    unix_path("/work"),
    ambient,
    DotenvOptions::new(commands=[
      try! @host.CommandSpec::new("sh", ["-c", "emit"]),
    ]),
  )
  assert_eq(preserved.get("TOKEN"), None)
  let override_host = @host.FakeHost::new(
    unix_path("/work"),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let override_expected = try! @host.CommandSpec::new("sh", ["-c", "emit"])
  override_expected.set_cwd(unix_path("/work"))
  override_host.expect_process(
    override_expected,
    @host.ProcessResult::new(0, b"TOKEN=dotenv", b""),
  )
  let overridden = load_dotenv_commands(
    override_host,
    unix_path("/work"),
    ambient,
    DotenvOptions::new(override_environment=true, commands=[
      try! @host.CommandSpec::new("sh", ["-c", "emit"]),
    ]),
  )
  assert_eq(overridden.get("TOKEN"), Some("dotenv"))
  let failure_host = @host.FakeHost::new(
    unix_path("/work"),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let failing = try! @host.CommandSpec::new("sh", ["-c", "contains-secret"])
  failing.set_cwd(unix_path("/work"))
  failure_host.expect_process(
    failing,
    @host.ProcessResult::new(42, b"", b"secret diagnostic"),
  )
  try
    ignore(
      load_dotenv_commands(
        failure_host,
        unix_path("/work"),
        ambient,
        DotenvOptions::new(commands=[
          try! @host.CommandSpec::new("sh", ["-c", "contains-secret"]),
        ]),
      ),
    )
  catch {
    CommandFailed(index~, exit_code~) => {
      assert_eq(index, 1)
      assert_eq(exit_code, 42)
      let error : DotenvError = CommandFailed(index~, exit_code~)
      assert_eq(error.exit_code(), 42)
      assert_false(error.message().contains("secret"))
    }
    error => fail("unexpected command failure: \{Repr(error)}")
  } noraise {
    _ => fail("expected command failure")
  }
  let unavailable_host = @host.FakeHost::new(
    unix_path("/work"),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  try
    ignore(
      load_dotenv_commands(
        unavailable_host,
        unix_path("/work"),
        ambient,
        DotenvOptions::new(commands=[
          try! @host.CommandSpec::new("sh", ["-c", "structural-secret"]),
        ]),
      ),
    )
  catch {
    CommandUnavailable(index=1) => {
      let error : DotenvError = CommandUnavailable(index=1)
      assert_false(error.message().contains("secret"))
      assert_false("\{Repr(error)}".contains("secret"))
    }
    error => fail("unexpected unavailable command error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unavailable command failure")
  }
}

///|
test "dotenv invalid UTF-8 diagnostics contain path but no bytes" {
  let host = @host.FakeHost::new(
    unix_path("/work"),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let path = unix_path("/work/.env")
  host.put_file(path, Bytes::from_array([0xff]))
  try
    ignore(
      load_dotenv_files(
        host,
        unix_path("/work"),
        EnvTable::new(),
        DotenvOptions::new(load=true),
      ),
    )
  catch {
    InvalidUtf8(path=actual) => {
      assert_eq(actual, path)
      let error : DotenvError = InvalidUtf8(path=actual)
      assert_false(error.message().contains("255"))
    }
    error => fail("unexpected UTF-8 error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid UTF-8 failure")
  }
}

///|
test "host environment snapshots are sorted and capability checked" {
  let host = @host.FakeHost::new(
    unix_path("/work"),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  host.set_env("Z", "last")
  host.set_env("A", "first")
  assert_eq(snapshot(host).keys(), ["A", "Z"])
  host.deny(Environment)
  try snapshot(host) catch {
    CapabilityDenied(Environment) => ()
    error => fail("unexpected capability error: \{Repr(error)}")
  } noraise {
    _ => fail("expected environment denial")
  }
}

///|
test "environment name mode models Windows ASCII-insensitive lookup" {
  let sensitive = EnvTable::from_entries([("Path", "shell")][:])
  assert_false(sensitive.contains("PATH"))
  let windows = EnvTable::from_entries(
    [("Path", "shell")][:],
    name_mode=AsciiInsensitive,
  )
  assert_eq(windows.get("PATH"), Some("shell"))
  windows.set("PATH", "updated")
  assert_eq(windows.entries(), [("Path", "updated")])
  let host = @host.FakeHost::new(
    unix_path("/work"),
    @host.PlatformInfo::new(Windows, "x86_64", Windows),
  )
  host.put_file(unix_path("/work/.env"), b"PATH=dotenv")
  let loaded = load_dotenv_files(
    host,
    unix_path("/work"),
    windows,
    DotenvOptions::new(load=true),
  )
  assert_eq(loaded.get("PATH"), None)
}

///|
test "environment table merge and error rendering expose keys but not values" {
  let table = EnvTable::from_entries([("A", "secret-a")][:])
  assert_eq(table.name_mode(), Sensitive)
  let incoming = EnvTable::from_entries(
    [("A", "secret-b"), ("B", "secret-c")][:],
  )
  table.merge(incoming, override_existing=false)
  assert_eq(table.get("A"), Some("secret-a"))
  assert_eq(table.get("B"), Some("secret-c"))
  table.merge(incoming)
  assert_eq(table.get("A"), Some("secret-b"))
  let list_error : DotenvError = ArgumentsRequireLists
  assert_true(list_error.message().contains("require `set lists`"))
  assert_false(list_error.message().contains("secret"))
  let missing : DotenvError = Required
  assert_eq(missing.message(), "dotenv file not found")
}

///|
test "variable overrides parse module paths reject invalid names and use last wins" {
  let table = try! OverrideTable::from_entries(
    [("root", "first"), ("release::target", "nested"), ("root", "last")][:],
  )
  assert_eq(table.entries().length(), 2)
  assert_eq(table.get("root").unwrap().value(), "last")
  let nested = table.get("release::target").unwrap()
  assert_eq(nested.modules(), ["release"])
  assert_eq(nested.name(), "target")
  assert_eq(nested.path(), "release::target")
  for invalid in ["", "::name", "name::", "name:::value", "9name", "na.me"] {
    try VariableOverride::parse(invalid, "secret") catch {
      InvalidOverridePath(path~) => assert_eq(path, invalid)
      error => fail("unexpected override error: \{Repr(error)}")
    } noraise {
      _ => fail("expected invalid override path")
    }
  }
}

///|
test "platform configuration selects environment name rules explicitly" {
  let unix = PlatformConfiguration::new(
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let windows = PlatformConfiguration::new(
    @host.PlatformInfo::new(Windows, "x86_64", Windows),
  )
  assert_false(unix.is_windows())
  assert_eq(unix.environment_name_mode(), Sensitive)
  assert_true(windows.is_windows())
  assert_eq(windows.environment_name_mode(), AsciiInsensitive)
  let host = @host.FakeHost::new(
    unix_path("/work"),
    @host.PlatformInfo::new(Windows, "aarch64", Windows),
  )
  assert_eq(
    (try! platform_configuration(host)).info().architecture(),
    "aarch64",
  )
  host.deny(Platform)
  try platform_configuration(host) catch {
    CapabilityDenied(Platform) => ()
    error => fail("unexpected platform error: \{Repr(error)}")
  } noraise {
    _ => fail("expected platform capability denial")
  }
}

///|
test "shell precedence matches CLI setting and platform table" {
  let unix = PlatformConfiguration::new(
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let windows = PlatformConfiguration::new(
    @host.PlatformInfo::new(Windows, "x86_64", Windows),
  )
  let configured = try! ShellConfiguration::new("fish", ["-c"])
  let windows_configured = try! ShellConfiguration::new("pwsh", [
    "-NoLogo", "-Command",
  ])
  let default_shell = try! resolve_shell(unix)
  assert_eq(default_shell.program(), "sh")
  assert_eq(default_shell.arguments(), ["-cu"])
  let setting = try! resolve_shell(unix, setting_shell=Some(configured))
  assert_eq(setting.program(), "fish")
  let platform = try! resolve_shell(
    windows,
    setting_shell=Some(configured),
    windows_shell=Some(windows_configured),
    windows_powershell=true,
  )
  assert_eq(platform.program(), "pwsh")
  let powershell = try! resolve_shell(windows, windows_powershell=true)
  assert_eq(powershell.program(), "powershell.exe")
  assert_eq(powershell.arguments(), ["-NoLogo", "-Command"])
}

///|
test "CLI shell and arguments independently override platform settings" {
  let windows = PlatformConfiguration::new(
    @host.PlatformInfo::new(Windows, "x86_64", Windows),
  )
  let platform_shell = try! ShellConfiguration::new("pwsh", ["-Command"])
  let program_only = try! resolve_shell(
    windows,
    cli_shell=Some("bash"),
    windows_shell=Some(platform_shell),
  )
  assert_eq(program_only.program(), "bash")
  assert_eq(program_only.arguments(), ["-cu"])
  let arguments_only = try! resolve_shell(
    windows,
    cli_arguments=Some(["-e", "-c"]),
    windows_shell=Some(platform_shell),
  )
  assert_eq(arguments_only.program(), "sh")
  assert_eq(arguments_only.arguments(), ["-e", "-c"])
  let both = try! resolve_shell(
    windows,
    cli_shell=Some("zsh"),
    cli_arguments=Some([]),
    windows_shell=Some(platform_shell),
  )
  assert_eq(both.program(), "zsh")
  assert_eq(both.arguments(), [])
  try ShellConfiguration::new("", ["-c"]) catch {
    EmptyShell => ()
    error => fail("unexpected empty shell error: \{Repr(error)}")
  } noraise {
    _ => fail("expected empty shell rejection")
  }
}

///|
test "temporary directory CLI setting and host precedence is lexical" {
  let project = unix_path("/work/project")
  let cli = try! resolve_temporary_directory(
    project,
    cli_tempdir=Some("cli/tmp"),
    setting_tempdir=Some("setting/tmp"),
  )
  assert_eq(cli.source(), CommandLine)
  assert_eq(cli.directory().unwrap(), unix_path("/work/project/cli/tmp"))
  let setting = try! resolve_temporary_directory(
    project,
    setting_tempdir=Some("/var/tmp/just"),
  )
  assert_eq(setting.source(), Setting)
  assert_eq(setting.directory().unwrap(), unix_path("/var/tmp/just"))
  let fallback = try! resolve_temporary_directory(project)
  assert_eq(fallback.source(), HostDefault)
  assert_eq(fallback.directory(), None)
}

///|
test "process environment precedence table is complete" {
  let ambient = EnvTable::from_entries(
    [("AMBIENT", "ambient"), ("ORDER", "ambient"), ("REMOVED", "ambient")][:],
  )
  let dotenv = EnvTable::from_entries(
    [("DOTENV", "dotenv"), ("ORDER", "dotenv")][:],
  )
  let exported = EnvTable::from_entries(
    [("EXPORTED", "exported"), ("ORDER", "exported")][:],
  )
  let parameters = EnvTable::from_entries(
    [
      ("PARAMETER", "parameter"),
      ("ORDER", "parameter"),
      ("REMOVED", "parameter"),
    ][:],
  )
  let recipe = EnvTable::from_entries(
    [("RECIPE", "recipe"), ("ORDER", "recipe")][:],
  )
  let composed = compose_process_environment(
    ambient,
    dotenv,
    exported,
    parameters,
    recipe,
    unexports=["REMOVED"],
  )
  assert_eq(composed.get("AMBIENT"), Some("ambient"))
  assert_eq(composed.get("DOTENV"), Some("dotenv"))
  assert_eq(composed.get("EXPORTED"), Some("exported"))
  assert_eq(composed.get("PARAMETER"), Some("parameter"))
  assert_eq(composed.get("RECIPE"), Some("recipe"))
  assert_eq(composed.get("REMOVED"), Some("parameter"))
  assert_eq(composed.get("ORDER"), Some("recipe"))
}

///|
test "unexport removes inherited values and Windows removal is insensitive" {
  let windows = EnvTable::from_entries(
    [("Path", "secret")][:],
    name_mode=AsciiInsensitive,
  )
  windows.remove("PATH")
  assert_eq(windows.entries(), [])
  let composed = compose_process_environment(
    EnvTable::from_entries([("TOKEN", "ambient-secret")][:]),
    EnvTable::new(),
    EnvTable::new(),
    EnvTable::new(),
    EnvTable::new(),
    unexports=["TOKEN"],
  )
  assert_eq(composed.get("TOKEN"), None)
}

///|
test "aggregate environment configuration keeps all CLI decisions explicit" {
  let configuration = try! EnvironmentConfiguration::new(
    @host.PlatformInfo::new(Linux, "aarch64", Unix),
    unix_path("/project"),
    [("mode", "release")][:],
    cli_shell=Some("bash"),
    cli_shell_arguments=Some(["-eu", "-c"]),
    cli_tempdir=Some("tmp"),
  )
  assert_eq(configuration.platform().info().architecture(), "aarch64")
  assert_eq(configuration.overrides().get("mode").unwrap().value(), "release")
  assert_eq(configuration.shell().program(), "bash")
  assert_eq(configuration.shell().arguments(), ["-eu", "-c"])
  assert_eq(
    configuration.temporary_directory().directory().unwrap(),
    unix_path("/project/tmp"),
  )
}
