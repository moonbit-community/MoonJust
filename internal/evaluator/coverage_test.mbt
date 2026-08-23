///|
test "evaluator coverage exercises typed error messages and diagnostics" {
  let span = @source.Span::new(@source.SourceId::new(9910), 0, 1)
  let parse = @parser.ParserError::ExtraneousInput(span~)
  let errors : Array[@evaluator.EvaluationError] = [
    Parse(parse),
    UndefinedVariable(name="x", span~),
    VariableCycle(name="x", stack=["x", "x"], span~),
    VariableCycle(name="x", stack=["x", "y", "x"], span~),
    TypeMismatch(expected="string", actual="list", span~),
    Builtin(Unknown(name="missing"), span~),
    EffectRequired(effect="process", span~),
    Host(InvalidInput("host"), span~),
    ProcessFailure(code=7, span~),
    BacktickFailure(code=8, span~),
    ProcessSignaled(signal=Terminate, span~),
    InvalidUtf8(span~),
    RecursionLimitExceeded(limit=2, span~),
    FunctionRecursionLimit(name="f", limit=2, span~),
    NodeLimitExceeded(limit=3, span~),
    OutputLimitExceeded(limit=4, span~),
    MissingContext(fact="cwd", span~),
    ArgumentCount(recipe="build", expected="1", actual=2, span~),
    UnknownOverrides(names=["x", "y"], span~),
    FunctionArgumentCount(name="f", expected=1, actual=2, span~),
    EmptyParameter(recipe="build", parameter="args", span~),
  ]
  for error in errors {
    assert_true(error.code().has_prefix("MJ-EVAL-"))
    assert_eq(error.span(), span)
    assert_true(error.message().length() > 0)
    let diagnostic = try! error.to_diagnostic()
    assert_eq(diagnostic.code(), error.code())
  }
}

///|
async test "evaluator async effects cover shell, lazy assignments, and lookup" {
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix, portable_runtime=true),
  )
  let context = @evaluator.EvaluationContext::new(cwd~, lists=true, process_environment=[
    ("MODE", "async"),
  ])
  let shell = @evaluator.EffectShell::new("sh", ["-cu"])
  let span = @source.Span::origin(@source.SourceId::new(9911))

  let command = try! @host.CommandSpec::new("sh", ["-cu", "printf async"])
  command.set_cwd(cwd)
  command.set_inherit_environment(false)
  try! command.add_environment("MODE", "async")
  command.set_inherit_stdin(true)
  command.set_stdout(Capture)
  command.set_stderr(Inherit)
  host.expect_process(command, @host.ProcessResult::new(0, b"async", b""))
  assert_eq(
    try! @evaluator.evaluate_with_async_effects(
      host,
      host,
      expression("`printf async`"),
      context,
      shell,
    ),
    String("async"),
  )

  let compilation = try! @semantic.compile_source(
    @source.Source::from_text(
      @source.SourceId::new(9912),
      "async.just",
      "set export\nbase := 'base'\nvalue := base + `printf -x`\nunused := 'unused'\n",
    ),
    allow_unstable=true,
  )
  let async_command = try! @host.CommandSpec::new("sh", ["-cu", "printf -x"])
  async_command.set_cwd(cwd)
  async_command.set_inherit_environment(false)
  try! async_command.add_environment("MODE", "async")
  async_command.set_inherit_stdin(true)
  async_command.set_stdout(Capture)
  async_command.set_stderr(Inherit)
  host.expect_process(async_command, @host.ProcessResult::new(0, b"-x", b""))
  let environment = try! @evaluator.evaluate_compilation_with_async_effects_selected(
    host,
    host,
    compilation,
    context,
    shell,
    ["value"],
    overrides=[("base", "override")],
  )
  assert_eq(environment.get("base"), Some(String("override")))
  assert_eq(environment.get("value"), Some(String("override-x")))
  assert_true(environment.is_exported("base"))

  let lookup = try! @path.PathValue::new("/usr/bin/tool", Unix)
  host.set_env("PATH", "/usr/bin")
  host.put_file(lookup, b"tool")
  assert_eq(
    try! @evaluator.evaluate_with_async_effects(
      host,
      host,
      expression("which('tool')"),
      context,
      shell,
    ),
    List([String("/usr/bin/tool")]),
  )
  assert_eq(host.pending_process_expectations(), 0)

  let dry = try! @evaluator.evaluate_with_async_effects(
    host,
    host,
    expression("`printf dry`"),
    context,
    shell,
    dry_run=true,
  )
  assert_eq(dry, String("`printf dry`"))

  let recipe_compilation = try! @semantic.compile_source(
    @source.Source::from_text(
      @source.SourceId::new(9913),
      "params.just",
      "run value='default' *rest:\n  echo {{value}} {{rest}}\n",
    ),
    allow_unstable=true,
  )
  let recipe = recipe_compilation.recipe("run").unwrap()
  let bound = try! @evaluator.bind_recipe_parameters_with_async_effects(
    host,
    host,
    recipe,
    [],
    @evaluator.Environment::new(),
    context,
    shell,
  )
  assert_eq(bound.get("value"), Some(String("default")))
  assert_eq(bound.get("rest"), Some(List([])))
  assert_eq(host.pending_process_expectations(), 0)

  try
    @evaluator.evaluate_with_async_effects(
      host,
      host,
      expression("which('tool')"),
      @evaluator.EvaluationContext::new(cwd~),
      shell,
    )
  catch {
    Builtin(Failure(message~), ..) =>
      assert_true(message.contains("requires `set lists`"))
    error => fail("unexpected async list-mode error: \{Repr(error)}")
  } noraise {
    _ => fail("expected async list-mode error")
  }
  let _ = span
}

///|
async test "evaluator async expression state machine covers values operators and functions" {
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let context = @evaluator.EvaluationContext::new(cwd~, lists=true)
  let shell = @evaluator.EffectShell::new("sh", ["-cu"])
  let environment = @evaluator.Environment::new()
  environment.set("known", String("value"))
  let compilation = try! @semantic.compile_source(
    @source.Source::from_text(
      @source.SourceId::new(9914),
      "functions.just",
      "decorate(x) := x + '-ok'\n",
    ),
    allow_unstable=true,
  )
  let functions = @evaluator.FunctionEnvironment::from_compilation(compilation)
  let cases = [
    ("'text'", @value.Value::String("text")),
    ("true", Bool(true)),
    ("known", String("value")),
    ("decorate('x')", String("x-ok")),
    ("['a', 'b']", List([String("a"), String("b")])),
    ("!false", Bool(true)),
    ("'a' == 'a'", Bool(true)),
    ("'a' != 'b'", Bool(true)),
    ("'abc' =~ 'b'", Bool(true)),
    ("'abc' !~ 'z'", Bool(true)),
    ("['a'] ++ ['b']", List([String("a"), String("b")])),
    ("'a' + 'b'", String("ab")),
    ("'a' / 'b'", String("a/b")),
    ("true || error('unused')", Bool(true)),
    ("false && error('unused')", List([])),
    ("if false { 'no' } else { 'yes' }", String("yes")),
    ("if false { 'no' }", List([])),
    ("f'prefix {{known}} suffix'", String("prefix value suffix")),
    ("(known)", String("value")),
  ]
  for row in cases {
    let actual = try! @evaluator.evaluate_with_async_effects(
      host,
      host,
      expression(row.0),
      context,
      shell,
      environment~,
      functions~,
    )
    if actual != row.1 {
      fail(
        "async expression mismatch for `\{row.0}`: " +
        "expected \{Repr(row.1)}, got \{Repr(actual)}",
      )
    }
  }

  for invalid in ["missing", "decorate()"] {
    try
      @evaluator.evaluate_with_async_effects(
        host,
        host,
        expression(invalid),
        context,
        shell,
        environment~,
        functions~,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("expected async evaluation failure")
    }
  }
  try
    @evaluator.evaluate_with_async_effects(
      host,
      host,
      expression("!!!true"),
      context,
      shell,
      limits=@evaluator.EvaluationLimits::new(2, 100, 100),
    )
  catch {
    RecursionLimitExceeded(..) => ()
    error => fail("unexpected async recursion limit: \{Repr(error)}")
  } noraise {
    _ => fail("expected async recursion limit")
  }
  try
    @evaluator.evaluate_with_async_effects(
      host,
      host,
      expression("true && true"),
      context,
      shell,
      limits=@evaluator.EvaluationLimits::new(128, 1, 100),
    )
  catch {
    NodeLimitExceeded(..) => ()
    error => fail("unexpected async node limit: \{Repr(error)}")
  } noraise {
    _ => fail("expected async node limit")
  }
  try
    @evaluator.evaluate_with_async_effects(
      host,
      host,
      expression("'0123456789'"),
      context,
      shell,
      limits=@evaluator.EvaluationLimits::new(128, 100, 4),
    )
  catch {
    OutputLimitExceeded(..) => ()
    error => fail("unexpected async output limit: \{Repr(error)}")
  } noraise {
    _ => fail("expected async output limit")
  }
}

///|
async test "evaluator async non-process effects use explicit host context" {
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  host.set_env("MODE", "async")
  host.set_clock_millis(0L)
  host.set_random_stream(b"1234567890123456")
  host.set_terminal(@host.TerminalInfo::new(true, true, true, true))
  host.put_file(try! @path.PathValue::new("/workspace/input", Unix), b"abc")
  let context = @evaluator.EvaluationContext::new(
    cwd~,
    lists=true,
    utc_offset_seconds=3600,
    color_mode="always",
  )
  let shell = @evaluator.EffectShell::new("sh", ["-cu"])
  let cases = [
    ("arch()", "x86_64"),
    ("os()", "linux"),
    ("os_family()", "unix"),
    ("env('MODE')", "async"),
    ("env('MISSING', 'fallback')", "fallback"),
    ("absolute_path('input')", "/workspace/input"),
    ("read('input')", "abc"),
    ("datetime_utc('%Y-%m-%d')", "1970-01-01"),
    ("style('red', 'text')", "\u{001b}[31mtext\u{001b}[0m"),
  ]
  for row in cases {
    let value = try
      @evaluator.evaluate_with_async_effects(
        host,
        host,
        expression(row.0),
        context,
        shell,
      )
    catch {
      error => fail("async effect `\{row.0}` failed: \{Repr(error)}")
    } noraise {
      value => value
    }
    assert_eq(value.to_string(), row.1)
  }
  assert_eq(
    try! @evaluator.evaluate_with_async_effects(
      host,
      host,
      expression("path_exists('input')"),
      context,
      shell,
    ),
    String("true"),
  )
  assert_true(
    (try! @evaluator.evaluate_with_async_effects(
      host,
      host,
      expression("uuid()"),
      context,
      shell,
    ))
    .to_string()
    .length() ==
    36,
  )
  let written = try! @evaluator.call_non_process_effect_with_context(
    host,
    "write",
    [String("output"), String("data")],
    context,
    @source.Span::origin(@source.SourceId::new(9915)),
  )
  assert_eq(written, String(""))
  assert_eq(
    try! @host.HostFs::read_file(
      host,
      try! @path.PathValue::new("/workspace/output", Unix),
    ),
    b"data",
  )
}

///|
test "evaluator synchronous state machine covers list algebra and assertions" {
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let lists = @evaluator.EvaluationContext::new(cwd~, lists=true)
  let plain = @evaluator.EvaluationContext::new(cwd~)
  let environment = @evaluator.Environment::new()
  environment.set("known", String("value"))
  let compilation = try! @semantic.compile_source(
    @source.Source::from_text(
      @source.SourceId::new(9916),
      "sync-functions.just",
      "decorate(x) := x + '-ok'\n",
    ),
    allow_unstable=true,
  )
  let functions = @evaluator.FunctionEnvironment::from_compilation(compilation)
  let cases = [
    ("known", @value.Value::String("value")),
    ("decorate('x')", String("x-ok")),
    ("['a'] + ['b', 'c']", List([String("ab"), String("ac")])),
    ("['a', 'b'] + ['c']", List([String("ac"), String("bc")])),
    ("['a', 'b'] + ['c', 'd']", List([String("ac"), String("bd")])),
    ("true || false", Bool(true)),
    ("true && true", Bool(true)),
    ("if true { 'yes' } else { 'no' }", String("yes")),
  ]
  for row in cases {
    assert_eq(
      try! @evaluator.evaluate(expression(row.0), environment~, functions~),
      row.1,
    )
  }
  assert_eq(
    try! @evaluator.evaluate_with_context(expression("assert(true)"), lists),
    Bool(true),
  )
  assert_eq(
    try! @evaluator.evaluate_with_context(expression("assert(true)"), plain),
    String(""),
  )
  for
    invalid in [
      "[] + ['a']", "assert(false)", "assert(false, 'custom')", "assert()", "assert(true, 'a', 'b')",
    ] {
    try @evaluator.evaluate_with_context(expression(invalid), lists) catch {
      Builtin(_, ..) => ()
      error => fail("unexpected sync expression error: \{Repr(error)}")
    } noraise {
      _ => fail("expected sync expression failure for \{invalid}")
    }
  }
  for invalid in ["true || false", "['a'] ++ ['b']", "['a']", "!true"] {
    try @evaluator.evaluate_with_context(expression(invalid), plain) catch {
      Builtin(_, ..) => ()
      error => fail("unexpected list-mode error: \{Repr(error)}")
    } noraise {
      _ => fail("expected list-mode failure for \{invalid}")
    }
  }
  for expression_text in ["read('input')", "`echo input`"] {
    try
      @evaluator.evaluate_with_context(expression(expression_text), lists)
    catch {
      EffectRequired(..) => ()
      error => fail("unexpected effect requirement: \{Repr(error)}")
    } noraise {
      _ => fail("expected effect requirement for \{expression_text}")
    }
  }
  try
    @evaluator.evaluate_with_context(
      expression("decorate()"),
      lists,
      functions~,
    )
  catch {
    FunctionArgumentCount(..) => ()
    error => fail("unexpected function arity error: \{Repr(error)}")
  } noraise {
    _ => fail("expected function arity failure")
  }
  assert_eq(
    try! @evaluator.evaluate_source(
      @source.Source::from_text(
        @source.SourceId::new(9917),
        "expression.just",
        "'source' + '-value'",
      ),
    ),
    String("source-value"),
  )
}
