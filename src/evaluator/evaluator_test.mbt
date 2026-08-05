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
fn fake() -> @host.FakeHost raise @path.PathError {
  let cwd = @path.PathValue::new("/workspace", Unix)
  @host.FakeHost::new(cwd, @host.PlatformInfo::new(Linux, "x86_64", Unix))
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
