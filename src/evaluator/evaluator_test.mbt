///|
fn expression(text : String) -> @syntax.Expression {
  let source = @source.Source::from_text(
    @source.SourceId::new(50),
    "expr",
    text,
  )
  try! @parser.parse_expression(source)
}

///|
test "pure evaluation supports conditions, lists, concatenation and builtins" {
  let environment = Environment::new()
  environment.set("name", String("Moon"))
  assert_eq(
    evaluate(expression("name + \"Bit\""), environment~),
    String("MoonBit"),
  )
  assert_eq(
    evaluate(expression("if true { uppercase(\"ok\") } else { \"no\" }")),
    String("OK"),
  )
  assert_eq(
    evaluate(expression("[\"a\"] ++ [\"b\"]")),
    List([String("a"), String("b")]),
  )
  try evaluate(expression("env_var(\"MODE\")")) catch {
    EffectRequired(effect="env_var", ..) => ()
    _ => fail("unexpected pure/effect boundary error")
  } noraise {
    _ => fail("expected effect requirement")
  }
}

///|
test "compilation evaluates forward references and rejects cycles" {
  let source = @source.Source::from_text(
    @source.SourceId::new(51),
    "justfile",
    "a := b + \"!\"\nb := \"ok\"\n",
  )
  let compilation = try! @semantic.compile_source(source)
  let environment = try! evaluate_compilation(compilation)
  assert_eq(environment.get("a"), Some(String("ok!")))
  let cyclic = @source.Source::from_text(
    @source.SourceId::new(52),
    "justfile",
    "a := b\nb := a\n",
  )
  let compilation = try! @semantic.compile_source(cyclic)
  try evaluate_compilation(compilation) catch {
    VariableCycle(_) => ()
    _ => fail("unexpected evaluation error")
  } noraise {
    _ => fail("expected variable cycle")
  }
}

///|
test "command-line overrides enter lazy evaluation before dependencies" {
  let source = @source.Source::from_text(
    @source.SourceId::new(521),
    "justfile",
    "set export\nbase := 'debug'\nderived := base + '-mode'\n",
  )
  let compilation = try! @semantic.compile_source(source)
  let environment = try! evaluate_compilation(compilation, overrides=[
    ("base", "release"),
    ("base", "final"),
  ])
  assert_eq(environment.get("base"), Some(String("final")))
  assert_eq(environment.get("derived"), Some(String("final-mode")))
  assert_true(environment.is_exported("base"))
  try
    evaluate_compilation(compilation, overrides=[
      ("z-missing", "secret-z"),
      ("a-missing", "secret-a"),
    ])
  catch {
    UnknownOverrides(names~, ..) => assert_eq(names, ["a-missing", "z-missing"])
    error => fail("unexpected override error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unknown override")
  }
}

///|
test "lazy environment evaluates only dependencies of a selected expression" {
  let source = @source.Source::from_text(
    @source.SourceId::new(522),
    "justfile",
    "unused := env_var('MISSING')\ndir := base + '/child'\nbase := 'root'\n",
  )
  let environment = LazyEnvironment::new(try! @semantic.compile_source(source))
  assert_eq(
    environment.evaluate_expression(expression("dir")),
    String("root/child"),
  )
  assert_true(environment.state("unused") is Some(Unevaluated))
}

///|
test "recipe variable references include dependencies and function bodies" {
  let source = @source.Source::from_text(
    @source.SourceId::new(523),
    "justfile",
    "x := 'x'\ny := 'y'\nunused := 'no'\nf(p) := p + x\nfoo: bar\n\nbar:\n  echo {{f(y)}}\n",
  )
  let compilation = try! @semantic.compile_source(source, allow_unstable=true)
  assert_eq(recipe_variable_references(compilation, ["foo"]), ["x", "y"])
}

///|
fn fake() -> @host.FakeHost raise @path.PathError {
  let cwd = @path.PathValue::new("/workspace", Unix)
  @host.FakeHost::new(cwd, @host.PlatformInfo::new(Linux, "x86_64", Unix))
}

///|
async test "portable canonicalize rejects a missing final path component" {
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix, portable_runtime=true),
  )
  try
    evaluate_with_async_effects(
      host,
      host,
      expression("canonicalize('missing')"),
      EvaluationContext::new(cwd~),
      EffectShell::new("sh", ["-cu"]),
    )
  catch {
    Builtin(Failure(message~), ..) => {
      assert_true(message.contains("canonicalizing `missing`"))
      assert_true(message.contains("NotFound"))
    }
    error => fail("unexpected canonicalize error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing canonical path failure")
  }
  assert_eq(host.pending_process_expectations(), 0)
}

///|
test "effect builtins use deterministic host capabilities" {
  let host = fake()
  let cwd = @path.PathValue::new("/workspace", Unix)
  let span = try! @source.Span::new(@source.SourceId::new(53), 0, 0)
  host.set_env("MODE", "test")
  host.set_clock_millis(42L)
  host.set_random_stream(b"12345678901234561234567890123456")
  host.put_file(@path.PathValue::new("/workspace/input", Unix), b"abc")
  assert_eq(
    call_effect(host, "env", [String("MODE")], cwd, span),
    String("test"),
  )
  assert_eq(
    call_effect(
      host,
      "env_var_or_default",
      [String("MISSING"), String("fallback")],
      cwd,
      span,
    ),
    String("fallback"),
  )
  assert_eq(call_effect(host, "arch", [], cwd, span), String("x86_64"))
  assert_eq(call_effect(host, "os", [], cwd, span), String("linux"))
  assert_eq(
    call_effect(host, "require", [String("/workspace/input")], cwd, span),
    String("/workspace/input"),
  )
  assert_eq(call_effect(host, "now_millis", [], cwd, span), String("42"))
  assert_eq(
    call_effect(host, "sha256_file", [String("/workspace/input")], cwd, span),
    String("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
  )
  assert_eq(
    call_effect(host, "blake3_file", [String("/workspace/input")], cwd, span),
    String("6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85"),
  )
  assert_true(
    call_effect(host, "uuid", [], cwd, span).to_string().length() == 36,
  )
  let uuid = call_effect(host, "uuid", [], cwd, span).to_string()
  assert_eq(uuid[14], '4')
  assert_true(
    uuid[19] == '8' || uuid[19] == '9' || uuid[19] == 'a' || uuid[19] == 'b',
  )
}

///|
test "evaluation limits reject adversarial depth" {
  let limits = EvaluationLimits::new(2, 100, 100)
  try evaluate(expression("!!!true"), limits~) catch {
    RecursionLimitExceeded(_) => ()
    _ => fail("unexpected limit error")
  } noraise {
    _ => fail("expected recursion limit")
  }
}

///|
test "node and rendered-output budgets are enforced" {
  try
    evaluate(
      expression("true && true"),
      limits=EvaluationLimits::new(128, 1, 100),
    )
  catch {
    NodeLimitExceeded(_) => ()
    _ => fail("unexpected node budget error")
  } noraise {
    _ => fail("expected node budget error")
  }
  try
    evaluate(
      expression("\"0123456789\""),
      limits=EvaluationLimits::new(128, 100, 4),
    )
  catch {
    OutputLimitExceeded(_) => ()
    _ => fail("unexpected output budget error")
  } noraise {
    _ => fail("expected output budget error")
  }
}

///|
test "child environments snapshot and track exports" {
  let parent = Environment::new()
  parent.set("A", String("parent"))
  let child = Environment::child(parent)
  child.set("A", String("child"))
  child.set("B", String("value"))
  child.mark_exported("B")
  assert_eq(parent.get("A"), Some(String("parent")))
  assert_eq(child.get("A"), Some(String("child")))
  assert_true(child.is_exported("B"))
  assert_eq(child.names(), ["A", "B"])
}

///|
test "evaluation context supplies invocation facts without ambient fallbacks" {
  let context = EvaluationContext::new(
    cwd=@path.PathValue::new("/work", Unix),
    recipe="build",
    module_name="tools",
    source=@source.SourceId::new(60),
    justfile=@path.PathValue::new("/work/justfile", Unix),
    source_file=@path.PathValue::new("/work/imports/tasks.just", Unix),
    module_file=@path.PathValue::new("/work/modules/tools.just", Unix),
    module_path="tools",
    executable=@path.PathValue::new("/bin/just", Unix),
    executable_directory=@path.PathValue::new("/opt/bin", Unix),
    invocation_directory=@path.PathValue::new("/invoked", Unix),
    invocation_directory_native=@path.PathValue::new("/native-invoked", Unix),
    pid=4242,
    num_cpus=8,
    num_jobs=3,
    is_dependency=true,
  )
  assert_eq(
    evaluate_with_context(
      expression("recipe_name() + \"@\" + module_path()"),
      context,
    ),
    String("build@tools"),
  )
  assert_eq(
    evaluate_with_context(expression("source_directory()"), context),
    String("/work/imports"),
  )
  assert_eq(
    evaluate_with_context(expression("absolute_path(\"a/../b\")"), context),
    String("/work/b"),
  )
  assert_eq(
    evaluate_with_context(expression("is_dependency()"), context),
    String("true"),
  )
  assert_eq(
    evaluate_with_context(
      expression("is_dependency()"),
      EvaluationContext::new(is_dependency=false),
    ),
    String("false"),
  )
  assert_eq(
    evaluate_with_context(expression("executable_directory()"), context),
    String("/opt/bin"),
  )
  assert_eq(
    evaluate_with_context(expression("invocation_directory_native()"), context),
    String("/native-invoked"),
  )
  try
    evaluate_with_context(expression("just_pid()"), EvaluationContext::new())
  catch {
    MissingContext(fact="just_pid", ..) => ()
    _ => fail("unexpected missing-context error")
  } noraise {
    _ => fail("expected missing context")
  }
}

///|
test "effect context connects fs random clock process terminal and PATH facts" {
  let host = fake()
  let cwd = @path.PathValue::new("/workspace", Unix)
  let span = try! @source.Span::new(@source.SourceId::new(61), 0, 0)
  let context = EvaluationContext::new(
    cwd~,
    invocation_directory=cwd,
    justfile=@path.PathValue::new("/workspace/justfile", Unix),
    executable=@path.PathValue::new("/bin/just", Unix),
    pid=99,
    num_cpus=4,
    num_jobs=2,
    lists=true,
    utc_offset_seconds=3600,
  )
  host.set_env("PATH", "/bin:/usr/bin")
  host.put_file(@path.PathValue::new("/usr/bin/tool", Unix), b"binary")
  host.put_file(@path.PathValue::new("/workspace/input", Unix), b"abc")
  host.set_canonical(
    @path.PathValue::new("/workspace/link", Unix),
    @path.PathValue::new("/workspace/input", Unix),
  )
  host.set_clock_millis(0L)
  host.set_random_stream(
    b"\x00\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00" + b"1234567890123456",
  )
  host.set_terminal(@host.TerminalInfo::new(true, true, true, true))
  assert_eq(
    call_effect_with_context(
      host,
      "canonicalize",
      [String("link")],
      context,
      span,
    ),
    String("/workspace/input"),
  )
  assert_eq(
    call_effect_with_context(host, "which", [String("tool")], context, span),
    List([String("/usr/bin/tool")]),
  )
  assert_eq(
    call_effect_with_context(
      host,
      "choose",
      [String("3"), String("abc")],
      context,
      span,
    ),
    String("abc"),
  )
  assert_eq(
    call_effect_with_context(
      host,
      "datetime",
      [String("%Y-%m-%d %H:%M:%S %z")],
      context,
      span,
    ),
    String("1970-01-01 01:00:00 +0100"),
  )
  assert_eq(
    call_effect_with_context(
      host,
      "datetime_utc",
      [String("%Y-%m-%dT%H:%M:%S%:z")],
      context,
      span,
    ),
    String("1970-01-01T00:00:00+00:00"),
  )
  try
    call_effect_with_context(
      host,
      "datetime",
      [String("%Y")],
      EvaluationContext::new(cwd~),
      span,
    )
  catch {
    MissingContext(fact="utc_offset_seconds", ..) => ()
    _ => fail("unexpected local-time context error")
  } noraise {
    _ => fail("expected explicit local-time offset")
  }
  assert_eq(
    call_effect_with_context(
      host,
      "style",
      [List([String("bold"), String("red")]), String("alert")],
      context,
      span,
    ),
    String("\u{001b}[1;31malert\u{001b}[0m"),
  )
  assert_eq(
    call_effect_with_context(
      host,
      "style",
      [List([String("bg:blue"), String("#0f0")]), String("ok")],
      context,
      span,
    ),
    String("\u{001b}[44;38;2;0;255;0mok\u{001b}[0m"),
  )
  host.set_terminal(@host.TerminalInfo::new(false, false, false, false))
  assert_eq(
    call_effect_with_context(
      host,
      "style",
      [String("red"), String("always-styled")],
      EvaluationContext::new(cwd~),
      span,
    ),
    String("\u{001b}[31malways-styled\u{001b}[0m"),
  )
  assert_eq(
    call_effect_with_context(
      host,
      "style",
      [List([String("red"), String("stdout")]), String("plain")],
      EvaluationContext::new(cwd~),
      span,
    ),
    String("plain"),
  )
  assert_eq(
    call_effect_with_context(
      host,
      "style",
      [List([String("red"), String("stdout")]), String("forced")],
      EvaluationContext::new(cwd~, color_mode="always"),
      span,
    ),
    String("\u{001b}[31mforced\u{001b}[0m"),
  )
  host.set_terminal(@host.TerminalInfo::new(true, true, true, true))
  assert_eq(
    call_effect_with_context(
      host,
      "style",
      [List([String("red"), String("stdout")]), String("never")],
      EvaluationContext::new(cwd~, color_mode="never"),
      span,
    ),
    String("never"),
  )
  let command = @host.CommandSpec::new("sh", [
    "-cu", "printf %s $1", "printf %s $1", "ok",
  ])
  command.set_cwd(cwd)
  command.set_inherit_stdin(true)
  command.set_stdout(Capture)
  command.set_stderr(Inherit)
  host.expect_process(command, @host.ProcessResult::new(0, b"ok\n", b""))
  assert_eq(
    call_effect_with_context(
      host,
      "shell",
      [String("printf %s $1"), String("ok")],
      context,
      span,
    ),
    String("ok"),
  )
  assert_eq(host.pending_process_expectations(), 0)
}

///|
test "configured shell captures stdout and removes exactly one line ending" {
  let host = fake()
  let cwd = @path.PathValue::new("/workspace", Unix)
  let span = try! @source.Span::new(@source.SourceId::new(71), 4, 12)
  let context = EvaluationContext::new(cwd~)
  let shell = EffectShell::new("bash", ["-eu", "-c"])
  let command = @host.CommandSpec::new("bash", [
    "-eu", "-c", "emit", "emit", "arg",
  ])
  command.set_cwd(cwd)
  command.set_inherit_stdin(true)
  command.set_stdout(Capture)
  command.set_stderr(Inherit)
  host.expect_process(
    command,
    @host.ProcessResult::new(0, b"value  \r\n\n", b"visible\n"),
  )
  assert_eq(
    call_shell_effect(
      host,
      [String("emit"), String("arg")],
      context,
      shell,
      span,
    ),
    String("value  \r\n"),
  )
}

///|
test "nested backticks use the effect handler while pure evaluation stays denied" {
  let host = fake()
  let cwd = @path.PathValue::new("/workspace", Unix)
  let context = EvaluationContext::new(cwd~)
  let shell = EffectShell::new("sh", ["-cu"])
  let command = @host.CommandSpec::new("sh", ["-cu", "printf ok"])
  command.set_cwd(cwd)
  command.set_inherit_stdin(true)
  command.set_stdout(Capture)
  command.set_stderr(Inherit)
  host.expect_process(command, @host.ProcessResult::new(0, b"ok\n", b""))
  let expression = try! @parser.parse_expression(
    @source.Source::from_text(@source.SourceId::new(73), "expr", "`printf ok`"),
  )
  assert_eq(
    evaluate_with_effects(host, expression, context, shell),
    String("ok"),
  )
  try evaluate(expression) catch {
    EffectRequired(effect="process", ..) => ()
    _ => fail("unexpected pure evaluation result")
  } noraise {
    _ => fail("expected pure effect denial")
  }
}

///|
test "quiet shell discards stderr and preserves typed failures" {
  let host = fake()
  let cwd = @path.PathValue::new("/workspace", Unix)
  let span = try! @source.Span::new(@source.SourceId::new(72), 0, 4)
  let context = EvaluationContext::new(cwd~)
  let shell = EffectShell::new("powershell.exe", ["-NoLogo", "-Command"])
  let failed = @host.CommandSpec::new("powershell.exe", [
    "-NoLogo", "-Command", "exit 17",
  ])
  failed.set_cwd(cwd)
  failed.set_inherit_stdin(true)
  failed.set_stdout(Capture)
  failed.set_stderr(Discard)
  host.expect_process(failed, @host.ProcessResult::new(17, b"", b""))
  try
    evaluate_backtick_with_shell(
      host,
      "exit 17",
      context,
      shell,
      span,
      quiet=true,
    )
  catch {
    BacktickFailure(code=17, span=error_span) => assert_eq(error_span, span)
    error => fail("unexpected backtick failure: \{Repr(error)}")
  } noraise {
    _ => fail("expected backtick failure")
  }
  let signaled = @host.CommandSpec::new("powershell.exe", [
    "-NoLogo", "-Command", "stop",
  ])
  signaled.set_cwd(cwd)
  signaled.set_inherit_stdin(true)
  signaled.set_stdout(Capture)
  signaled.set_stderr(Inherit)
  host.expect_process(
    signaled,
    @host.ProcessResult::from_signal(Terminate, b"", b""),
  )
  try evaluate_backtick_with_shell(host, "stop", context, shell, span) catch {
    ProcessSignaled(signal=Terminate, ..) => ()
    error => fail("unexpected backtick signal: \{Repr(error)}")
  } noraise {
    _ => fail("expected backtick signal")
  }
}

///|
test "effect failures preserve typed capability and arity diagnostics" {
  let host = fake()
  let cwd = @path.PathValue::new("/workspace", Unix)
  let span = try! @source.Span::new(@source.SourceId::new(62), 0, 0)
  let context = EvaluationContext::new(cwd~, invocation_directory=cwd)
  try
    call_effect_with_context(host, "choose", [String("1")], context, span)
  catch {
    Builtin(Arity(name="choose", expected="2", actual=1), ..) => ()
    _ => fail("unexpected arity error")
  } noraise {
    _ => fail("expected arity error")
  }
  host.deny(FsRead)
  try
    call_effect_with_context(
      host,
      "path_exists",
      [String("input")],
      context,
      span,
    )
  catch {
    Host(CapabilityDenied(FsRead), ..) => ()
    _ => fail("unexpected capability error")
  } noraise {
    _ => fail("expected denied filesystem capability")
  }
  try
    call_effect_with_context(
      host,
      "style",
      [String("not-a-style"), String("text")],
      context,
      span,
    )
  catch {
    Builtin(Failure(message="invalid style: `not-a-style`"), ..) => ()
    _ => fail("unexpected style validation error")
  } noraise {
    _ => fail("expected style validation error")
  }
}

///|
test "lazy assignments expose states and redact cycle diagnostics" {
  let source = @source.Source::from_text(
    @source.SourceId::new(63),
    "justfile",
    "a := b + \"!\"\nb := \"ok\"\n",
  )
  let lazy_env = LazyEnvironment::new(try! @semantic.compile_source(source))
  assert_true(lazy_env.state("a") is Some(Unevaluated))
  assert_eq(lazy_env.resolve("a"), String("ok!"))
  assert_true(lazy_env.state("a") is Some(Evaluated(String("ok!"))))
  assert_true(lazy_env.state("b") is Some(Evaluated(String("ok"))))

  let conditional = @source.Source::from_text(
    @source.SourceId::new(69),
    "justfile",
    "set lists\nselected := if true { \"ok\" } else { bad }\n" +
    "bad := error(\"unreachable\")\n",
  )
  let lazy_env = LazyEnvironment::new(
    try! @semantic.compile_source(conditional, allow_unstable=true),
  )
  assert_eq(lazy_env.resolve("selected"), String("ok"))

  let cyclic = @source.Source::from_text(
    @source.SourceId::new(64),
    "justfile",
    "secret := \"must-not-leak\"\na := b\nb := a\n",
  )
  let lazy_env = LazyEnvironment::new(try! @semantic.compile_source(cyclic))
  try ignore(lazy_env.resolve("a")) catch {
    VariableCycle(name="a", stack=["a", "b", "a"], ..) as error =>
      assert_true(!error.message().contains("must-not-leak"))
    _ => fail("unexpected cycle stack")
  } noraise {
    _ => fail("expected cycle")
  }
  assert_true(lazy_env.state("a") is Some(Unevaluated))
  assert_true(lazy_env.state("b") is Some(Unevaluated))
}

///|
test "lazy assignments separate undefined names and bound recursion depth" {
  let undefined = @source.Source::from_text(
    @source.SourceId::new(65),
    "justfile",
    "a := \"ok\"\n",
  )
  let lazy_env = LazyEnvironment::new(try! @semantic.compile_source(undefined))
  try lazy_env.resolve("missing") catch {
    UndefinedVariable(name="missing", ..) => ()
    _ => fail("unexpected undefined-variable error")
  } noraise {
    _ => fail("expected undefined variable")
  }
  let deep = @source.Source::from_text(
    @source.SourceId::new(66),
    "justfile",
    "a := b\nb := c\nc := \"ok\"\n",
  )
  let lazy_env = LazyEnvironment::new(
    try! @semantic.compile_source(deep),
    limits=EvaluationLimits::new(2, 100, 100),
  )
  try lazy_env.resolve("a") catch {
    RecursionLimitExceeded(limit=2, ..) => ()
    _ => fail("unexpected lazy recursion error")
  } noraise {
    _ => fail("expected bounded lazy recursion")
  }
}

///|
test "recipe and module scopes implement defaults variadics shadowing and exports" {
  let parent = Environment::new()
  parent.set("base", String("release"))
  parent.set("private", String("hidden"))
  parent.set("public", String("visible"))
  parent.mark_exported("public")
  let defaults = @source.Source::from_text(
    @source.SourceId::new(67),
    "justfile",
    "base := \"release\"\nbuild $mode=base:\n",
  )
  let recipe = try! @semantic.compile_source(defaults).recipe("build").unwrap()
  let scope = bind_recipe_parameters(recipe, [], parent)
  assert_eq(scope.get("mode"), Some(String("release")))
  assert_true(scope.is_exported("mode"))
  scope.set("base", String("debug"))
  assert_eq(parent.get("base"), Some(String("release")))

  let variadic = @source.Source::from_text(
    @source.SourceId::new(68),
    "justfile",
    "pack first +rest:\n",
  )
  let recipe = try! @semantic.compile_source(variadic).recipe("pack").unwrap()
  let scope = bind_recipe_parameters(
    recipe,
    [String("a"), String("b"), String("c")],
    parent,
  )
  assert_eq(scope.get("first"), Some(String("a")))
  assert_eq(scope.get("rest"), Some(List([String("b"), String("c")])))
  try bind_recipe_parameters(recipe, [], parent) catch {
    ArgumentCount(recipe="pack", ..) => ()
    _ => fail("unexpected recipe arity error")
  } noraise {
    _ => fail("expected required variadic argument")
  }

  let star = @source.Source::from_text(
    @source.SourceId::new(70),
    "justfile",
    "collect *items:\n",
  )
  let recipe = try! @semantic.compile_source(star).recipe("collect").unwrap()
  let scope = bind_recipe_parameters(recipe, [], parent)
  assert_eq(scope.get("items"), Some(String("")))
  let list_scope = bind_recipe_parameters(recipe, [], parent, lists=true)
  assert_eq(list_scope.get("items"), Some(List([])))

  let optional = @source.Source::from_text(
    @source.SourceId::new(71),
    "justfile",
    "optional flag:\n",
  )
  let recipe = try! @semantic.compile_source(optional)
    .recipe("optional")
    .unwrap()
  let scope = bind_recipe_parameters(
    recipe,
    [],
    parent,
    allow_empty=Set(["flag"]),
  )
  assert_eq(scope.get("flag"), Some(List([])))

  let module_env = Environment::module_scope(parent)
  assert_eq(module_env.get("public"), Some(String("visible")))
  assert_eq(module_env.get("private"), None)
  assert_true(module_env.is_exported("public"))
}

///|
test "user functions shadow builtins capture outer values and use bounded recursion" {
  let source = @source.Source::from_text(
    @source.SourceId::new(801),
    "justfile",
    "set unstable\nouter := 'outer'\nbool(value) := value\nf(outer) := bool(outer)\nresult := f('inner')\n",
  )
  let compilation = try! @semantic.compile_source(source)
  let environment = try! evaluate_compilation(compilation)
  assert_eq(environment.get("result"), Some(String("inner")))
  let recursive = @source.Source::from_text(
    @source.SourceId::new(802),
    "justfile",
    "set unstable\nf() := f()\nresult := f()\n",
  )
  let compilation = try! @semantic.compile_source(recursive)
  try
    evaluate_compilation(
      compilation,
      limits=EvaluationLimits::new(8, 1000, 1000),
    )
  catch {
    FunctionRecursionLimit(name="f", limit=8, ..) => ()
    error => fail("unexpected function recursion error: \{Repr(error)}")
  } noraise {
    _ => fail("expected bounded function recursion")
  }
}
