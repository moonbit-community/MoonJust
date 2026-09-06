///|
fn eval_upstream_function_text(text : String) -> String raise EvaluationError {
  let source = @source.Source::from_text(
    @source.SourceId::new(707),
    "expr",
    text,
  )
  evaluate_source(source).to_string()
}

///|
fn assert_upstream_function_error(
  text : String,
  expected : String,
) -> Unit raise {
  try eval_upstream_function_text(text) catch {
    Builtin(Failure(message~), ..) => assert_eq(message, expected)
    _ => fail("unexpected evaluation error")
  } noraise {
    _ => fail("expected evaluation error")
  }
}

///|
fn assert_shell_invocation(
  command : String,
  arguments : Array[String],
  expected_arguments : Array[String],
  expected_output : String,
) -> Unit raise {
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let expected = try! @host.CommandSpec::new("sh", expected_arguments)
  expected.set_cwd(cwd)
  expected.set_inherit_stdin(true)
  expected.set_stderr(Inherit)
  host.expect_process(
    expected,
    @host.ProcessResult::new(0, @utf8.encode(expected_output), b""),
  )
  let values : Array[@value.Value] = [String(command)]
  for argument in arguments {
    values.push(String(argument))
  }
  let value = try! call_shell_effect(
    host,
    values,
    EvaluationContext::new(cwd~),
    EffectShell::new("sh", ["-cu"]),
    @source.Span::origin(@source.SourceId::new(935)),
  )
  assert_eq(value.to_string(), expected_output.trim_end().to_owned())
  assert_eq(host.pending_process_expectations(), 0)
}

///|
test "upstream functions::path_functions" {
  assert_eq(
    try! eval_upstream_function_text("without_extension('/foo/bar/baz.hello')"),
    "/foo/bar/baz",
  )
  assert_eq(
    try! eval_upstream_function_text("file_stem('/foo/bar/baz.hello')"),
    "baz",
  )
  assert_eq(
    try! eval_upstream_function_text("file_name('/foo/bar/baz.hello')"),
    "baz.hello",
  )
  assert_eq(
    try! eval_upstream_function_text("parent_directory('/foo/bar/baz.hello')"),
    "/foo/bar",
  )
  assert_eq(
    try! eval_upstream_function_text("extension('/foo/bar/baz.hello')"),
    "hello",
  )
  assert_eq(try! eval_upstream_function_text("join('a', 'b')"), "a/b")
}

///|
test "upstream functions::path_functions2" {
  assert_eq(
    try! eval_upstream_function_text("without_extension('/foo/bar/baz')"),
    "/foo/bar/baz",
  )
  assert_eq(
    try! eval_upstream_function_text("file_stem('/foo/bar/baz.hello.ciao')"),
    "baz.hello",
  )
  assert_eq(
    try! eval_upstream_function_text("file_name('/bar/baz.hello.ciao')"),
    "baz.hello.ciao",
  )
  assert_eq(try! eval_upstream_function_text("parent_directory('/foo/')"), "/")
  assert_eq(
    try! eval_upstream_function_text("extension('/foo/bar/baz.hello.ciao')"),
    "ciao",
  )
}

///|
test "upstream functions::shell_minimal" {
  assert_shell_invocation(
    "echo $1 $2",
    ["justice", "legs"],
    ["-cu", "echo $1 $2", "echo $1 $2", "justice", "legs"],
    "justice legs\n",
  )
}

///|
test "upstream functions::shell_first_arg" {
  assert_shell_invocation(
    "echo $0",
    [],
    ["-cu", "echo $0", "echo $0"],
    "echo $0\n",
  )
}

///|
test "upstream functions::shell_args" {
  assert_shell_invocation(
    "echo $@",
    ["justice", "legs"],
    ["-cu", "echo $@", "echo $@", "justice", "legs"],
    "justice legs\n",
  )
}

///|
test "upstream functions::broken_directory_function" {
  assert_upstream_function_error(
    "parent_directory('')", "call to function `parent_directory` failed: could not extract parent directory from ``",
  )
}

///|
test "upstream functions::broken_directory_function2" {
  assert_upstream_function_error(
    "parent_directory('/')", "call to function `parent_directory` failed: could not extract parent directory from `/`",
  )
}

///|
test "upstream functions::broken_extension_function" {
  assert_upstream_function_error(
    "extension('')", "call to function `extension` failed: could not extract extension from ``",
  )
}

///|
test "upstream functions::broken_extension_function2" {
  assert_upstream_function_error(
    "extension('foo')", "call to function `extension` failed: could not extract extension from `foo`",
  )
}

///|
test "upstream functions::broken_file_name_function" {
  assert_upstream_function_error(
    "file_name('')", "call to function `file_name` failed: could not extract file name from ``",
  )
}

///|
test "upstream functions::broken_file_stem_function" {
  assert_upstream_function_error(
    "file_stem('')", "call to function `file_stem` failed: could not extract file stem from ``",
  )
}

///|
test "upstream functions::broken_without_extension_function" {
  assert_upstream_function_error(
    "without_extension('')", "call to function `without_extension` failed: could not extract parent from ``",
  )
}

///|
fn eval_upstream_context_function(
  text : String,
) -> String raise EvaluationError {
  let source = @source.Source::from_text(
    @source.SourceId::new(708),
    "expr",
    text,
  )
  let expression = @parser.parse_expression(source) catch {
    error => raise Parse(error)
  }
  evaluate_with_context(expression, EvaluationContext::new()).to_string()
}

///|
test "upstream functions::append" {
  assert_eq(
    try! eval_upstream_context_function("append('8', 'r s t')"),
    "r8 s8 t8",
  )
  assert_eq(
    try! eval_upstream_context_function("append('.c', 'main sar x11')"),
    "main.c sar.c x11.c",
  )
  assert_eq(
    try! eval_upstream_context_function("append('-', 'c v h y')"),
    "c- v- h- y-",
  )
  assert_eq(
    try! eval_upstream_context_function("append('0000', '11 10 01 00')"),
    "110000 100000 010000 000000",
  )
  assert_eq(
    try! eval_upstream_context_function(
      "append('tion', '\n    Determina\n    Acquisi\n    Motiva\n    Conjunc\n    ')",
    ),
    "Determination Acquisition Motivation Conjunction",
  )
}

///|
test "upstream functions::prepend" {
  assert_eq(
    try! eval_upstream_context_function("prepend('8', 'r s t')"),
    "8r 8s 8t",
  )
  assert_eq(
    try! eval_upstream_context_function("prepend('src/', 'main sar x11')"),
    "src/main src/sar src/x11",
  )
  assert_eq(
    try! eval_upstream_context_function("prepend('-', 'c v h y')"),
    "-c -v -h -y",
  )
  assert_eq(
    try! eval_upstream_context_function("prepend('0000', '11 10 01 00')"),
    "000011 000010 000001 000000",
  )
  assert_eq(
    try! eval_upstream_context_function(
      "prepend('April-', '\n      1st,\n        17th,\n    20th,\n    ')",
    ),
    "April-1st, April-17th, April-20th,",
  )
}

///|
test "upstream functions::encode_uri_component" {
  assert_eq(
    try! eval_upstream_function_text(
      "encode_uri_component(\"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!\\\"#$%&'()*+,-./:;<=>?@[\\\\]^_`{|}~ \\t\\r\\n🌐\")",
    ),
    "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!%22%23%24%25%26'()*%2B%2C-.%2F%3A%3B%3C%3D%3E%3F%40%5B%5C%5D%5E_%60%7B%7C%7D~%20%09%0D%0A%F0%9F%8C%90",
  )
}

///|
test "upstream functions::sha256" {
  assert_eq(
    try! eval_upstream_function_text(
      "sha256('5943ee37-0000-1000-8000-010203040506')",
    ),
    "2330d7f5eb94a820b54fed59a8eced236f80b633a504289c030b6a65aef58871",
  )
}

///|
test "upstream functions::blake3" {
  assert_eq(
    try! eval_upstream_function_text(
      "blake3('5943ee37-0000-1000-8000-010203040506')",
    ),
    "026c9f740a793ff536ddf05f8915ea4179421f47f0fa9545476076e9ba8f3f2b",
  )
}

///|
test "upstream functions::trim_end" {
  assert_eq(try! eval_upstream_function_text("trim_end('  f  ')"), "  f")
}

///|
test "upstream functions::trim_start" {
  assert_eq(try! eval_upstream_function_text("trim_start('  f  ')"), "f  ")
}

///|
test "upstream functions::trim_end_match" {
  assert_eq(
    try! eval_upstream_function_text("trim_end_match('foo', 'o')"),
    "fo",
  )
  assert_eq(
    try! eval_upstream_function_text("trim_end_match('fabab', 'ab')"),
    "fab",
  )
}

///|
test "upstream functions::trim_end_matches" {
  assert_eq(
    try! eval_upstream_function_text("trim_end_matches('foo', 'o')"),
    "f",
  )
  assert_eq(
    try! eval_upstream_function_text("trim_end_matches('fabab', 'ab')"),
    "f",
  )
  assert_eq(
    try! eval_upstream_function_text("trim_end_matches('fbaabab', 'ab')"),
    "fba",
  )
}

///|
test "upstream functions::trim_start_match" {
  assert_eq(
    try! eval_upstream_function_text("trim_start_match('oof', 'o')"),
    "of",
  )
  assert_eq(
    try! eval_upstream_function_text("trim_start_match('ababf', 'ab')"),
    "abf",
  )
}

///|
test "upstream functions::trim_start_matches" {
  assert_eq(
    try! eval_upstream_function_text("trim_start_matches('oof', 'o')"),
    "f",
  )
  assert_eq(
    try! eval_upstream_function_text("trim_start_matches('ababf', 'ab')"),
    "f",
  )
  assert_eq(
    try! eval_upstream_function_text("trim_start_matches('ababbaf', 'ab')"),
    "baf",
  )
}

///|
test "upstream functions::show_string" {
  assert_eq(try! eval_upstream_function_text("show(\"foo\")"), "\"foo\"")
}

///|
test "upstream functions::show_escapes_contents" {
  assert_eq(
    try! eval_upstream_function_text("show(\"a\\tb\\\"c\")"),
    "\"a\\tb\\\"c\"",
  )
}

///|
test "upstream functions::show_list" {
  assert_eq(
    try! eval_upstream_function_text("show([\"foo\", \"bar baz\", \"qux\"])"),
    "[\"foo\", \"bar baz\", \"qux\"]",
  )
}

///|
test "upstream functions::show_empty_list" {
  assert_eq(try! eval_upstream_function_text("show([])"), "[]")
}

///|
test "upstream functions::join_unix" {
  assert_eq(
    try! eval_upstream_function_text("join('a', 'b', 'c', 'd')"),
    "a/b/c/d",
  )
  assert_eq(
    try! eval_upstream_function_text("join('a', '/b', 'c', 'd')"),
    "/b/c/d",
  )
  assert_eq(
    try! eval_upstream_function_text("join('a', '/b', '/c', 'd')"),
    "/c/d",
  )
  assert_eq(
    try! eval_upstream_function_text("join('a', '/b', '/c', '/d')"),
    "/d",
  )
}

///|
test "upstream functions::join_windows" {
  let cwd = try! @path.PathValue::new("C:\\workspace", Windows)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Windows, "test", Windows),
  )
  let value = try! call_non_process_effect_with_context(
    host,
    "join",
    [String("a"), String("b"), String("c"), String("d")],
    EvaluationContext::new(cwd~),
    @source.Span::origin(@source.SourceId::new(715)),
  )
  assert_eq(value.to_string(), "a\\b\\c\\d")
  let rooted = try! call_non_process_effect_with_context(
    host,
    "join",
    [String("a"), String("\\b"), String("\\c"), String("d")],
    EvaluationContext::new(cwd~),
    @source.Span::origin(@source.SourceId::new(716)),
  )
  assert_eq(rooted.to_string(), "\\c\\d")
}

///|
test "upstream functions::shell_with_powershell" {
  let cwd = try! @path.PathValue::new("C:\\workspace", Windows)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Windows, "test", Windows),
  )
  let expected = try! @host.CommandSpec::new("pwsh.exe", [
    "-NoLogo", "-Command", "Write-Output bar",
  ])
  expected.set_cwd(cwd)
  expected.set_inherit_stdin(true)
  expected.set_stdout(Capture)
  expected.set_stderr(Inherit)
  host.expect_process(expected, @host.ProcessResult::new(0, b"bar\r\n", b""))
  let value = try! call_shell_effect(
    host,
    [String("Write-Output bar")],
    EvaluationContext::new(cwd~),
    EffectShell::new("pwsh.exe", ["-NoLogo", "-Command"]),
    @source.Span::origin(@source.SourceId::new(717)),
  )
  assert_eq(value.to_string(), "bar")
  assert_eq(host.pending_process_expectations(), 0)
}

///|
test "upstream functions::just_version" {
  let source = @source.Source::from_text(
    @source.SourceId::new(714),
    "expr",
    "just_version()",
  )
  let context = EvaluationContext::new()
  let expression = try! @parser.parse_expression(source)
  assert_eq(
    try! evaluate_with_context(expression, context).to_string(),
    "1.57.0",
  )
}

///|
test "upstream functions::module_path" {
  let source = @source.Source::from_text(
    @source.SourceId::new(715),
    "expr",
    "module_path()",
  )
  let context = EvaluationContext::new(module_path="")
  let expression = try! @parser.parse_expression(source)
  assert_eq(try! evaluate_with_context(expression, context).to_string(), "")
}

///|
test "upstream functions::is_dependency" {
  let source = @source.Source::from_text(
    @source.SourceId::new(716),
    "expr",
    "is_dependency()",
  )
  let expression = try! @parser.parse_expression(source)
  let root = EvaluationContext::new(is_dependency=false)
  let dependency = EvaluationContext::new(is_dependency=true)
  assert_eq(try! evaluate_with_context(expression, root).to_string(), "false")
  assert_eq(
    try! evaluate_with_context(expression, dependency).to_string(),
    "true",
  )
}

///|
test "upstream quote::single_quotes_are_prepended_and_appended" {
  assert_eq(try! eval_upstream_function_text("quote('abc')"), "'abc'")
}

///|
test "upstream quote::quotes_are_escaped" {
  assert_eq(try! eval_upstream_function_text("quote(\"'\")"), "''\\'''")
}
