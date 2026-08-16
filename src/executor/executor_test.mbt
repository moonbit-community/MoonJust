///|
fn source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(81), "justfile", text)
}

///|
fn compile_recipe(text : String) -> (@semantic.Compilation, @syntax.Recipe) {
  let compilation = try! @semantic.compile(try! @parser.parse(source(text)))
  (compilation, compilation.recipe("build").unwrap())
}

///|
fn unix_path(text : String) -> @path.PathValue {
  try! @path.PathValue::new(text, Unix)
}

///|
fn fake_host() -> @host.FakeHost {
  @host.FakeHost::new(
    unix_path("/workspace"),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
}

///|
fn spec(
  shell : @environment.ShellConfiguration,
  command : String,
) -> @host.CommandSpec {
  let arguments = shell.arguments().to_owned()
  arguments.push(command)
  let value = try! @host.CommandSpec::new(shell.program(), arguments)
  value.set_cwd(unix_path("/workspace"))
  value.set_inherit_environment(false)
  try! value.add_environment("MODE", "test")
  value.set_stdin(b"")
  value.set_stdout(Capture)
  value.set_stderr(Capture)
  value
}

///|
test "ordinary line evaluates interpolation and captures exact process request" {
  let (compilation, recipe) = compile_recipe(
    "name := \"world\"\nbuild:\n  echo hello {{name}}\n",
  )
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let host = fake_host()
  host.expect_process(
    spec(shell, "echo hello world"),
    @host.ProcessResult::new(0, b"hello world\n", b""),
  )
  let report = try! execute_recipe_lines(
    host,
    recipe,
    environment,
    shell,
    unix_path("/workspace"),
    process_environment=[("MODE", "test")],
  )
  assert_eq(report.stdout(), b"hello world\n")
  assert_eq(report.stderr(), b"echo hello world\n")
  assert_eq(report.commands(), 1)
  assert_eq(host.pending_process_expectations(), 0)
}

///|
test "quiet sigils and ignored failures retain child output" {
  let (compilation, recipe) = compile_recipe(
    "build:\n  @echo hidden\n  -false\n  echo visible\n",
  )
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let host = fake_host()
  host.expect_process(
    spec(shell, "echo hidden"),
    @host.ProcessResult::new(0, b"hidden\n", b""),
  )
  host.expect_process(
    spec(shell, "false"),
    @host.ProcessResult::new(7, b"", b"failure\n"),
  )
  host.expect_process(
    spec(shell, "echo visible"),
    @host.ProcessResult::new(0, b"visible\n", b""),
  )
  let report = try! execute_recipe_lines(
    host,
    recipe,
    environment,
    shell,
    unix_path("/workspace"),
    process_environment=[("MODE", "test")],
  )
  assert_eq(report.stdout(), b"hidden\nvisible\n")
  assert_eq(report.stderr(), b"false\nfailure\necho visible\n")
  assert_eq(report.commands(), 3)
}

///|
test "interpolation cannot synthesize a recipe line sigil" {
  let (compilation, recipe) = compile_recipe("build:\n  {{'@echo visible'}}\n")
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let host = fake_host()
  host.deny(Process)
  let report = try! execute_recipe_lines(
    host,
    recipe,
    environment,
    shell,
    unix_path("/workspace"),
    options=ExecutionOptions::new(dry_run=true),
  )
  assert_eq(report.stderr(), b"@echo visible\n")
}

///|
test "dry run echoes quiet lines and never grants process effects" {
  let (compilation, recipe) = compile_recipe(
    "build:\n  @echo hidden\n  -false\n",
  )
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let host = fake_host()
  host.deny(Process)
  let report = try! execute_recipe_lines(
    host,
    recipe,
    environment,
    shell,
    unix_path("/workspace"),
    options=ExecutionOptions::new(dry_run=true, quiet=true),
  )
  assert_eq(report.stderr(), b"echo hidden\nfalse\n")
  assert_eq(report.commands(), 0)
  assert_eq(host.process_calls().length(), 0)
}

///|
async test "script dry run preserves backticks without process or temp effects" {
  let compilation = try! @semantic.compile(
    try! @parser.parse(
      source("[script]\nbuild:\n  #!/bin/sh\n  echo {{`printf generated`}}\n"),
    ),
  )
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let host = fake_host()
  host.deny(Process)
  host.deny(FsWrite)
  let plan = try! plan_recipe_graph_async(
    host,
    host,
    compilation,
    [RecipeRequest::new("build")],
    environment,
    @evaluator.EvaluationContext::new(cwd=unix_path("/workspace")),
    shell,
    unix_path("/workspace"),
    ScriptConfiguration::new(
      shell,
      unix_path("/tmp"),
      @host.PlatformInfo::new(Linux, "test", Unix),
    ),
    options=ExecutionOptions::new(dry_run=true),
  )
  assert_eq(plan.steps().length(), 0)
  assert_eq(plan.stderr(), b"#!/bin/sh\necho `printf generated`\n")
  assert_eq(host.process_calls().length(), 0)
}

///|
async test "script attributes preserve inferred interpreter extension" {
  let compilation = try! @semantic.compile(
    try! @parser.parse(source("[script]\nbuild:\n  Write-Output platform\n")),
  )
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let interpreter = try! @environment.ShellConfiguration::new(
    "powershell.exe",
    ["-NoLogo", "-NoProfile", "-File"],
  )
  let host = fake_host()
  let plan = try! plan_recipe_graph_async(
    host,
    host,
    compilation,
    [RecipeRequest::new("build")],
    environment,
    @evaluator.EvaluationContext::new(cwd=unix_path("/workspace")),
    interpreter,
    unix_path("/workspace"),
    ScriptConfiguration::new(
      interpreter,
      unix_path("/tmp"),
      @host.PlatformInfo::new(Windows, "x86_64", Windows),
    ),
  )
  guard plan.steps()[0] is Script(script, _) else {
    fail("expected a planned script")
  }
  assert_eq(script.configuration().extension(), None)
  let materialized = try! materialize_script(host, script)
  assert_true(materialized.path().as_string().has_suffix(".ps1"))
  assert_eq(materialized.spec().arguments(), [
    "-NoLogo",
    "-NoProfile",
    "-File",
    materialized.path().as_string(),
  ])
}

///|
test "quiet discards child streams while verbose timestamp and color force echo" {
  let (compilation, recipe) = compile_recipe("@build:\n  @echo visible\n")
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let quiet_host = fake_host()
  let quiet_spec = try! @host.CommandSpec::new("sh", ["-cu", "echo visible"])
  quiet_spec.set_cwd(unix_path("/workspace"))
  quiet_spec.set_inherit_environment(false)
  quiet_spec.set_stdin(b"")
  quiet_spec.set_stdout(Discard)
  quiet_spec.set_stderr(Discard)
  quiet_host.expect_process(quiet_spec, @host.ProcessResult::new(0, b"", b""))
  let quiet = try! execute_recipe_lines(
    quiet_host,
    recipe,
    environment,
    shell,
    unix_path("/workspace"),
    options=ExecutionOptions::new(quiet=true),
  )
  assert_eq(quiet.stdout(), b"")
  assert_eq(quiet.stderr(), b"")

  let loud_host = fake_host()
  let loud_spec = try! @host.CommandSpec::new("sh", ["-cu", "echo visible"])
  loud_spec.set_cwd(unix_path("/workspace"))
  loud_spec.set_inherit_environment(false)
  loud_spec.set_stdin(b"")
  loud_spec.set_stdout(Capture)
  loud_spec.set_stderr(Capture)
  loud_host.expect_process(
    loud_spec,
    @host.ProcessResult::new(0, b"visible\n", b""),
  )
  let loud = try! execute_recipe_lines(
    loud_host,
    recipe,
    environment,
    shell,
    unix_path("/workspace"),
    options=ExecutionOptions::new(
      verbose=true,
      timestamp="12:34:56",
      command_color=Cyan,
    ),
  )
  assert_eq(
    loud.stderr(),
    b"[\x1b[1;36m12:34:56\x1b[0m] \x1b[1;36mecho visible\x1b[0m\n",
  )
  assert_eq(loud.stdout(), b"visible\n")
}

///|
test "elapsed and failure messages have stable golden output" {
  assert_eq(
    render_elapsed_message("build", 1234L),
    b"---> build completed in 1.234s\n",
  )
  let error = ExecutionError::command_failed("build", 2, 7)
  assert_eq(
    render_failure_message(error, true),
    b"error: recipe `build` failed on line 2 with exit code 7\n",
  )
  assert_eq(render_failure_message(error, false), b"")
}

///|
test "shell families preserve representative argv without quoting rewrites" {
  let (compilation, recipe) = compile_recipe("build:\n  echo a b\n")
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let cases = [
    try! @environment.ShellConfiguration::new("sh", ["-cu"]),
    try! @environment.ShellConfiguration::new("cmd.exe", ["/D", "/C"]),
    try! @environment.ShellConfiguration::new("powershell.exe", [
      "-NoLogo", "-Command",
    ]),
  ]
  for shell in cases {
    let host = fake_host()
    host.expect_process(
      spec(shell, "echo a b"),
      @host.ProcessResult::new(0, b"", b""),
    )
    ignore(
      try! execute_recipe_lines(
        host,
        recipe,
        environment,
        shell,
        unix_path("/workspace"),
        process_environment=[("MODE", "test")],
      ),
    )
    assert_eq(host.pending_process_expectations(), 0)
  }
}

///|
test "effectful recipe interpolation executes backtick before the shell line" {
  let (compilation, recipe) = compile_recipe(
    "build:\n  echo {{`printf generated`}}\n",
  )
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let host = fake_host()
  let effect = try! @host.CommandSpec::new("sh", ["-cu", "printf generated"])
  effect.set_cwd(unix_path("/workspace"))
  effect.set_inherit_stdin(true)
  effect.set_stdout(Capture)
  effect.set_stderr(Inherit)
  host.expect_process(effect, @host.ProcessResult::new(0, b"generated\n", b""))
  let line = try! @host.CommandSpec::new("sh", ["-cu", "echo generated"])
  line.set_cwd(unix_path("/workspace"))
  line.set_inherit_environment(false)
  line.set_stdin(b"")
  line.set_stdout(Capture)
  line.set_stderr(Capture)
  host.expect_process(line, @host.ProcessResult::new(0, b"generated\n", b""))
  let report = try! execute_recipe_lines_effectful(
    host,
    recipe,
    environment,
    shell,
    unix_path("/workspace"),
  )
  assert_eq(report.stdout(), b"generated\n")
  assert_eq(report.stderr(), b"echo generated\n")
  assert_eq(report.commands(), 1)
}

///|
test "unignored exit and signal failures stop later commands" {
  let (compilation, recipe) = compile_recipe("build:\n  first\n  second\n")
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let host = fake_host()
  host.expect_process(
    spec(shell, "first"),
    @host.ProcessResult::new(9, b"", b""),
  )
  try
    execute_recipe_lines(
      host,
      recipe,
      environment,
      shell,
      unix_path("/workspace"),
      process_environment=[("MODE", "test")],
    )
  catch {
    CommandFailed(recipe="build", line=1, exit_code=9) => ()
    error => fail("unexpected execution error: \{Repr(error)}")
  } noraise {
    _ => fail("expected command failure")
  }
  assert_eq(host.process_calls().length(), 1)

  let signaled_host = fake_host()
  signaled_host.expect_process(
    spec(shell, "first"),
    @host.ProcessResult::from_signal(Terminate, b"partial\n", b"warning\n"),
  )
  try
    execute_recipe_lines(
      signaled_host,
      recipe,
      environment,
      shell,
      unix_path("/workspace"),
      process_environment=[("MODE", "test")],
    )
  catch {
    CommandSignaled(recipe="build", line=1, signal=Terminate) as error =>
      assert_eq(error.exit_code(), 143)
    error => fail("unexpected signal error: \{Repr(error)}")
  } noraise {
    _ => fail("expected signal failure")
  }
}

///|
test "dependency graph is deterministic and once is keyed by parameter values" {
  let text = "leaf value:\n  @echo leaf-{{value}}\n" +
    "left: (leaf 'same')\n  @echo left\n" +
    "right: (leaf 'same') (leaf 'other')\n  @echo right\n" +
    "after:\n  @echo after\n" +
    "root: left right && after\n  @echo root\n"
  let compilation = try! @semantic.compile(try! @parser.parse(source(text)))
  let global = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let host = fake_host()
  for
    _, entry in [
      ("echo leaf-same", "leaf-same\n"),
      ("echo left", "left\n"),
      ("echo leaf-other", "leaf-other\n"),
      ("echo right", "right\n"),
      ("echo root", "root\n"),
      ("echo after", "after\n"),
    ] {
    let (command, output) = entry
    host.expect_process(
      spec(shell, command),
      @host.ProcessResult::new(0, @utf8.encode(output), b""),
    )
  }
  let report = try! execute_recipe_graph(
    host,
    compilation,
    [RecipeRequest::new("root")],
    global,
    shell,
    unix_path("/workspace"),
    process_environment=[("MODE", "test")],
  )
  assert_eq(
    report.stdout(),
    b"leaf-same\nleft\nleaf-other\nright\nroot\nafter\n",
  )
  assert_eq(report.stderr(), b"")
  assert_eq(report.commands(), 6)
  assert_eq(host.pending_process_expectations(), 0)
}

///|
test "duplicate root requests run once per exact argument vector" {
  let compilation = try! @semantic.compile(
    try! @parser.parse(source("build value:\n  @echo {{value}}\n")),
  )
  let global = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let host = fake_host()
  host.expect_process(
    spec(shell, "echo one"),
    @host.ProcessResult::new(0, b"one\n", b""),
  )
  host.expect_process(
    spec(shell, "echo two"),
    @host.ProcessResult::new(0, b"two\n", b""),
  )
  let report = try! execute_recipe_graph(
    host,
    compilation,
    [
      RecipeRequest::new("build", arguments=[String("one")]),
      RecipeRequest::new("build", arguments=[String("one")]),
      RecipeRequest::new("build", arguments=[String("two")]),
    ],
    global,
    shell,
    unix_path("/workspace"),
    process_environment=[("MODE", "test")],
  )
  assert_eq(report.stdout(), b"one\ntwo\n")
  assert_eq(report.commands(), 2)
}

///|
fn script_configuration(
  directory : String,
  interpreter : @environment.ShellConfiguration,
  extension? : String,
  operating_system? : @host.OperatingSystem = Linux,
) -> ScriptConfiguration {
  let platform = @host.PlatformInfo::new(operating_system, "x86_64", Unix)
  match extension {
    Some(value) =>
      ScriptConfiguration::new(
        interpreter,
        unix_path(directory),
        platform,
        extension=value,
      )
    None =>
      ScriptConfiguration::new(interpreter, unix_path(directory), platform)
  }
}

///|
test "shebang script uses executable temporary path and always cleans it" {
  let (compilation, recipe) = compile_recipe(
    "build:\n  #!/bin/sh\n  echo {{name}}\n".replace(
      old="build:\n",
      new="name := 'ok'\nbuild:\n",
    ),
  )
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let interpreter = try! @environment.ShellConfiguration::new("sh", ["-eu"])
  let host = fake_host()
  let path = unix_path("/tmp/space dir/build.0")
  let expected = try! @host.CommandSpec::new(path.as_string(), [])
  expected.set_cwd(unix_path("/workspace"))
  expected.set_inherit_environment(false)
  expected.set_stdin(b"")
  expected.set_stdout(Capture)
  expected.set_stderr(Capture)
  host.expect_process(expected, @host.ProcessResult::new(0, b"ok\n", b""))
  let report = try! execute_script_recipe(
    host,
    recipe,
    environment,
    unix_path("/workspace"),
    script_configuration("/tmp/space dir", interpreter),
  )
  assert_eq(report.stdout(), b"ok\n")
  assert_eq(host.script_temp_creations().length(), 1)
  assert_eq(host.script_temp_creations()[0].0, path)
  assert_eq(host.script_temp_creations()[0].1, b"#!/bin/sh\n\n\necho ok\n")
  assert_eq(host.executable_calls(), [path])
  assert_false(try! host.file_exists(path))
}

///|
test "configured interpreter keeps extension, normalizes CRLF, and cleans failure" {
  let (compilation, recipe) = compile_recipe(
    "[script]\r\nbuild:\r\n  echo one\r\n  echo two\r\n",
  )
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let interpreter = try! @environment.ShellConfiguration::new("python", ["-I"])
  let host = fake_host()
  let path = unix_path("/tmp/build.0.py")
  let expected = try! @host.CommandSpec::new("python", ["-I", path.as_string()])
  expected.set_cwd(unix_path("/workspace"))
  expected.set_inherit_environment(false)
  expected.set_stdin(b"")
  expected.set_stdout(Capture)
  expected.set_stderr(Capture)
  host.expect_process(expected, @host.ProcessResult::new(23, b"", b"bad\n"))
  try
    execute_script_recipe(
      host,
      recipe,
      environment,
      unix_path("/workspace"),
      script_configuration("/tmp", interpreter, extension=".py"),
    )
  catch {
    CommandFailed(recipe="build", line=0, exit_code=23) => ()
    error => fail("unexpected script error: \{Repr(error)}")
  } noraise {
    _ => fail("expected script failure")
  }
  assert_eq(host.script_temp_creations()[0].1, b"\n\necho one\necho two\n")
  assert_false(try! host.file_exists(path))
}

///|
test "PowerShell script selects ps1 and UTF-8 BOM" {
  let (compilation, recipe) = compile_recipe(
    "[script]\nbuild:\n  Write-Host caf\u{00e9}\n",
  )
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let interpreter = try! @environment.ShellConfiguration::new(
    "powershell.exe",
    ["-NoLogo", "-Command"],
  )
  let host = fake_host()
  let path = unix_path("/tmp/build.0.ps1")
  let expected = try! @host.CommandSpec::new("powershell.exe", [
    "-NoLogo",
    "-Command",
    path.as_string(),
  ])
  expected.set_cwd(unix_path("/workspace"))
  expected.set_inherit_environment(false)
  expected.set_stdin(b"")
  expected.set_stdout(Capture)
  expected.set_stderr(Capture)
  host.expect_process(expected, @host.ProcessResult::new(0, b"", b""))
  ignore(
    try! execute_script_recipe(
      host,
      recipe,
      environment,
      unix_path("/workspace"),
      script_configuration("/tmp", interpreter),
    ),
  )
  assert_eq(
    host.script_temp_creations()[0].1,
    @utf8.encode("\u{feff}\n\nWrite-Host caf\u{00e9}\n"),
  )
}

///|
test "script dry run and invalid shebang create no temporary files" {
  let (compilation, recipe) = compile_recipe("build:\n  #!\n  echo later\n")
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let interpreter = try! @environment.ShellConfiguration::new("sh", ["-eu"])
  let host = fake_host()
  let report = try! execute_script_recipe(
    host,
    recipe,
    environment,
    unix_path("/workspace"),
    script_configuration("/tmp", interpreter),
    options=ExecutionOptions::new(dry_run=true),
  )
  assert_eq(report.stderr(), b"#!\necho later\n")
  assert_eq(host.script_temp_creations().length(), 0)
  try
    execute_script_recipe(
      host,
      recipe,
      environment,
      unix_path("/workspace"),
      script_configuration("/tmp", interpreter),
    )
  catch {
    InvalidShebang(recipe="build", shebang="#!") => ()
    error => fail("unexpected shebang error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid shebang")
  }
  assert_eq(host.script_temp_creations().length(), 0)
}
