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
  host.set_random_stream(b"1234567890123456")
  host.put_file(@path.PathValue::new("/workspace/input", Unix), b"abc")
  assert_eq(
    call_effect(host, "env", [String("MODE")], cwd, span),
    String("test"),
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
