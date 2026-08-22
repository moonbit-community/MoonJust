///|
fn evaluator_coverage_span() -> @source.Span {
  @source.Span::origin(@source.SourceId::new(9920))
}

///|
test "evaluator whitebox coverage exercises context conversions" {
  let span = evaluator_coverage_span()
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let context = EvaluationContext::new(
    cwd~,
    recipe="build",
    module_name="tools",
    source=@source.SourceId::new(9920),
    justfile=cwd,
    source_file=cwd,
    source_files=[(@source.SourceId::new(9920), cwd)],
    module_file=cwd,
    module_path="tools",
    executable=cwd,
    executable_directory=cwd,
    invocation_directory=cwd,
    invocation_directory_native=cwd,
    home_directory=cwd,
    config_directory=cwd,
    config_local_directory=cwd,
    data_directory=cwd,
    data_local_directory=cwd,
    cache_directory=cwd,
    runtime_directory=cwd,
    pid=7,
    num_cpus=4,
    num_jobs=2,
    is_dependency=true,
    lists=true,
    utc_offset_seconds=3600,
    color_mode="always",
    command_color="red",
    environment=[("A", "B")],
    process_environment=[("P", "Q")],
  )
  assert_eq(context.recipe(), Some("build"))
  assert_eq(context.module_name(), Some("tools"))
  assert_eq(context.source(), Some(@source.SourceId::new(9920)))
  assert_eq(
    context.for_source(@source.SourceId::new(9920)).source_file(),
    Some(cwd),
  )
  assert_eq(context.for_recipe(cwd, "other", false).recipe(), Some("other"))
  assert_eq(
    context.with_process_environment([("X", "Y")]).process_environment,
    Some([("X", "Y")]),
  )
  assert_eq(split_ascii_whitespace(" a  b\t c "), ["a", "b", "c"])
  assert_eq(context_boolean(context, true), @value.Value::String("true"))
  assert_eq(context_boolean(context, false), @value.Value::List([]))
  assert_eq(
    map_context_paths(
      @value.Value::List([@value.Value::String("a"), @value.Value::String("b")]),
      context,
      span,
    ),
    @value.Value::List([
      @value.Value::String("/workspace/a"),
      @value.Value::String("/workspace/b"),
    ]),
  )
  assert_eq(
    context_parent("cwd", Some(cwd), span),
    try! @path.PathValue::new("/", Unix),
  )
  try context_parent("cwd", None, span) catch {
    MissingContext(fact="cwd", ..) => ()
    error => fail("unexpected missing context: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing context")
  }
  let _ = require_context_string("recipe", Some("build"), span)
  let _ = require_context_int("pid", Some(7), span)
  try require_context_string("recipe", None, span) catch {
    MissingContext(fact="recipe", ..) => ()
    _ => fail("expected missing string context")
  } noraise {
    _ => fail("expected missing string context")
  }
  try resolve_context_path(context, "../other", span) catch {
    _ => fail("relative path should resolve")
  } noraise {
    value => assert_eq(value.as_string(), "/other")
  }
}

///|
test "evaluator whitebox coverage exercises builtin context branches" {
  let span = evaluator_coverage_span()
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let scalar = EvaluationContext::new(cwd~, lists=true)
  let plain = EvaluationContext::new(cwd~)
  for
    row in [
      ("bool", [@value.Value::String("")], @value.Value::List([])),
      ("bool", [@value.Value::String("1")], @value.Value::String("true")),
      (
        "bool",
        [@value.Value::List([@value.Value::String("false")])],
        @value.Value::List([]),
      ),
      (
        "append",
        [@value.Value::String("!"), @value.Value::String("a b")],
        @value.Value::List([@value.Value::String("a b!")]),
      ),
      (
        "prepend",
        [
          @value.Value::String("x"),
          @value.Value::List([@value.Value::String("a")]),
        ],
        @value.Value::List([@value.Value::String("xa")]),
      ),
      (
        "show",
        [@value.Value::List([@value.Value::String("a")])],
        @value.Value::String("\"a\""),
      ),
    ] {
    let name = row.0
    let args = row.1
    let expected = row.2
    let value = try! context_builtin(name, args, scalar, span)
    assert_eq(value.unwrap(), expected)
  }
  let appended = try! context_builtin(
    "append",
    [@value.Value::String("!"), @value.Value::String("a b")],
    plain,
    span,
  )
  assert_eq(appended, Some(@value.Value::String("a! b!")))
  try
    context_builtin("bool", [@value.Value::String("maybe")], scalar, span)
  catch {
    Builtin(Failure(..), ..) => ()
    _ => fail("unexpected bool error")
  } noraise {
    _ => fail("expected bool error")
  }
  try
    context_builtin("bool", [@value.Value::String("true")], plain, span)
  catch {
    Builtin(Failure(..), ..) => ()
    _ => fail("unexpected list-mode error")
  } noraise {
    _ => fail("expected list-mode error")
  }
  try
    context_builtin("append", [@value.Value::String("x")], scalar, span)
  catch {
    _ => fail("wrong arity should fall through")
  } noraise {
    None => ()
    _ => ()
  }
  assert_eq(context_builtin("unknown-context", [], scalar, span), None)
}

///|
test "evaluator whitebox coverage exercises style and which helpers" {
  assert_eq(rgb_code("abc"), Some((170, 187, 204)))
  assert_eq(rgb_code("A1b2C3"), Some((161, 178, 195)))
  assert_eq(rgb_code("12"), None)
  assert_eq(rgb_code("ggg"), None)
  for style in ["bold", "fg:red", "bg:blue", "#abc", "bg:#112233", "15", "255"] {
    assert_true(style_code(style) is Some(_))
  }
  for style in ["fg:bold", "bg:italic", "#ggg", "256", "-1", "unknown"] {
    assert_eq(style_code(style), None)
  }
  let linux = @host.PlatformInfo::new(Linux, "x86_64", Unix)
  let windows = @host.PlatformInfo::new(Windows, "x86_64", Windows)
  assert_eq(which_extensions("tool", linux, None, evaluator_coverage_span()), [
    "",
  ])
  assert_eq(
    which_extensions(
      "tool.exe",
      windows,
      Some(".EXE;.BAT"),
      evaluator_coverage_span(),
    ),
    [""],
  )
  assert_eq(
    which_extensions(
      "tool",
      windows,
      Some(".EXE;.BAT"),
      evaluator_coverage_span(),
    ),
    ["", ".EXE", ".BAT"],
  )
  try
    which_extensions("tool", windows, Some("EXE"), evaluator_coverage_span())
  catch {
    Builtin(Failure(..), ..) => ()
    _ => fail("unexpected PATHEXT error")
  } noraise {
    _ => fail("expected PATHEXT error")
  }
  let context = EvaluationContext::new(
    cwd=try! @path.PathValue::new("/workspace", Unix),
  )
  let candidates = which_candidates(
    "tool",
    context,
    "/bin:/usr/bin",
    linux,
    None,
    evaluator_coverage_span(),
  )
  assert_eq(candidates.length(), 2)
  let direct = which_candidates(
    "/bin/tool",
    context,
    "",
    linux,
    None,
    evaluator_coverage_span(),
  )
  assert_eq(direct.length(), 1)
  assert_false(
    windows_candidate_is_executable(
      try! @path.PathValue::new("tool.exe", Windows),
      @host.FileMetadata::new(false, true, 1L),
      Some(".EXE"),
    ),
  )
  assert_true(
    windows_candidate_is_executable(
      try! @path.PathValue::new("tool.exe", Windows),
      @host.FileMetadata::new(true, false, 1L),
      Some(".EXE"),
    ),
  )
}

///|
test "evaluator whitebox coverage exercises datetime and reference traversal" {
  let span = evaluator_coverage_span()
  assert_eq(zero_pad(7, 3), "007")
  assert_eq(offset_text(0, true), "+00:00")
  assert_eq(offset_text(-19800, false), "-0530")
  for
    day in [
      @time.Weekday::Monday,
      @time.Weekday::Tuesday,
      @time.Weekday::Wednesday,
      @time.Weekday::Thursday,
      @time.Weekday::Friday,
      @time.Weekday::Saturday,
      @time.Weekday::Sunday,
    ] {
    assert_true(weekday_names(day).1.length() > 0)
  }
  for month in 1..<13 {
    assert_true(month_names(month).0.length() > 0)
  }
  let formats = [
    "%Y-%y-%m-%b-%B-%d-%e", "%H:%I:%M:%S.%f", "%a %A %j %p", "%z %:z %Z %s %%",
  ]
  for format in formats {
    assert_true(format_datetime(0L, 0, format, "datetime", span).length() > 0)
  }
  assert_true(
    format_datetime(-1L, -19800, "%s.%f", "datetime", span).contains("-1"),
  )
  for format in ["%", "%Q", "%#"] {
    try format_datetime(0L, 0, format, "datetime", span) catch {
      Builtin(Failure(..), ..) => ()
      error => fail("unexpected datetime error: \{Repr(error)}")
    } noraise {
      _ => fail("expected datetime format error")
    }
  }
  let source = @source.Source::from_text(
    @source.SourceId::new(9925),
    "references.just",
    "base := 'base'\nother := base\nf(x) := other + x\n" +
    "dep:\n  echo {{f('x')}} {{other}} {{base}}\nroot x='y': dep\n  echo {{x}}\n",
  )
  let compilation = try! @semantic.compile_source(source, allow_unstable=true)
  let refs = recipe_variable_references(compilation, ["dep"])
  assert_true(refs.contains("base"))
  assert_true(refs.contains("other"))
  assert_eq(resolved_recipe_name(compilation, "root"), Some("root"))
  assert_eq(resolved_recipe_name(compilation, "missing"), None)
}

///|
test "evaluator context accessors and builtins expose every invocation fact" {
  let span = evaluator_coverage_span()
  let path = try! @path.PathValue::new("/workspace/fact", Unix)
  let source_id = @source.SourceId::new(9926)
  let context = EvaluationContext::new(
    cwd=path,
    recipe="run",
    module_name="tools",
    source=source_id,
    justfile=path,
    source_file=path,
    source_files=[(source_id, path)],
    module_file=path,
    module_path="tools",
    executable=path,
    executable_directory=path,
    invocation_directory=path,
    invocation_directory_native=path,
    home_directory=path,
    config_directory=path,
    config_local_directory=path,
    data_directory=path,
    data_local_directory=path,
    cache_directory=path,
    runtime_directory=path,
    pid=11,
    num_cpus=8,
    num_jobs=3,
    is_dependency=true,
    lists=true,
    utc_offset_seconds=0,
    color_mode="always",
    command_color="green",
    environment=[("MODE", "test")],
    process_environment=[("PATH", "/bin")],
  )
  assert_eq(context.color_mode(), Some("always"))
  assert_eq(context.command_color(), Some("green"))
  assert_eq(context.cwd(), Some(path))
  assert_eq(context.justfile(), Some(path))
  assert_eq(context.source_file(), Some(path))
  assert_eq(context.module_file(), Some(path))
  assert_eq(context.module_path(), Some("tools"))
  assert_eq(context.executable(), Some(path))
  assert_eq(context.executable_directory(), Some(path))
  assert_eq(context.invocation_directory(), Some(path))
  assert_eq(context.invocation_directory_native(), Some(path))
  assert_eq(context.home_directory(), Some(path))
  assert_eq(context.config_directory(), Some(path))
  assert_eq(context.config_local_directory(), Some(path))
  assert_eq(context.data_directory(), Some(path))
  assert_eq(context.data_local_directory(), Some(path))
  assert_eq(context.cache_directory(), Some(path))
  assert_eq(context.runtime_directory(), Some(path))
  assert_eq(context.pid(), Some(11))
  assert_eq(context.num_cpus(), Some(8))
  assert_eq(context.num_jobs(), Some(3))
  assert_true(context.is_dependency())
  assert_true(context.lists())
  assert_eq(context.utc_offset_seconds(), Some(0))

  for
    name in [
      "cache_directory", "config_directory", "config_local_directory", "data_directory",
      "data_local_directory", "home_directory", "runtime_directory", "invocation_directory",
      "invocation_directory_native", "executable_directory", "justfile_directory",
      "source_directory", "module_directory", "just_executable", "justfile", "source_file",
      "module_file", "module_path", "just_pid", "num_cpus", "num_jobs", "is_dependency",
      "recipe_name", "just_version",
    ] {
    assert_true(context_builtin(name, [], context, span) is Some(_))
  }
  assert_eq(
    context_builtin(
      "env",
      [
        @value.Value::List([
          @value.Value::String("MISSING"),
          @value.Value::String("MODE"),
        ]),
      ],
      context,
      span,
    ),
    Some(@value.Value::String("test")),
  )
  assert_eq(
    context_builtin(
      "env_var_or_default",
      [@value.Value::String("MISSING"), @value.Value::String("fallback")],
      context,
      span,
    ),
    Some(@value.Value::String("fallback")),
  )
  assert_eq(
    context_builtin(
      "quote",
      [
        @value.Value::List([
          @value.Value::String("a b"),
          @value.Value::String("c"),
        ]),
      ],
      context,
      span,
    ),
    Some(
      @value.Value::List([
        @value.Value::String("'a b'"),
        @value.Value::String("'c'"),
      ]),
    ),
  )
  assert_eq(
    context_builtin(
      "semver_matches",
      [@value.Value::String("1.2.3"), @value.Value::String(">=1")],
      context,
      span,
    ),
    Some(@value.Value::String("true")),
  )
}

///|
test "evaluator helper failures preserve typed boundaries" {
  let span = evaluator_coverage_span()
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let shell = EffectShell::new("cmd.exe", ["/C"])
  assert_eq(shell.program(), "cmd.exe")
  assert_eq(shell.arguments(), ["/C"])
  assert_false(shell_takes_name("C:\\Windows\\cmd.exe"))
  assert_false(shell_takes_name("pwsh"))
  assert_true(shell_takes_name("/bin/sh"))
  assert_eq(strip_one_line_ending("a\r\n"), "a")
  assert_eq(strip_one_line_ending("a\n"), "a")
  assert_eq(strip_one_line_ending("a"), "a")
  assert_eq(bytes_text(b"valid", span), "valid")
  try bytes_text(b"\xff", span) catch {
    InvalidUtf8(_) => ()
    error => fail("unexpected UTF-8 error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid UTF-8")
  }
  try expect_string("test", [], 0, span) catch {
    TypeMismatch(actual="missing", ..) => ()
    error => fail("unexpected missing string error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing string")
  }
  try expect_string("test", [@value.Value::Bool(true)], 0, span) catch {
    TypeMismatch(actual="boolean", ..) => ()
    error => fail("unexpected string type error: \{Repr(error)}")
  } noraise {
    _ => fail("expected string type mismatch")
  }
  assert_eq(value_strings("test", @value.Value::String("x"), span), ["x"])
  assert_eq(
    value_strings(
      "test",
      @value.Value::List([@value.Value::String("x"), @value.Value::String("y")]),
      span,
    ),
    ["x", "y"],
  )
  for
    invalid in [
      @value.Value::Bool(true),
      @value.Value::List([@value.Value::Bool(true)]),
    ] {
    try value_strings("test", invalid, span) catch {
      TypeMismatch(_) => ()
      error => fail("unexpected value list error: \{Repr(error)}")
    } noraise {
      _ => fail("expected value list type mismatch")
    }
  }
  host.set_env("SECOND", "found")
  assert_eq(
    env_value(
      host,
      "env",
      @value.Value::List([
        @value.Value::String("FIRST"),
        @value.Value::String("SECOND"),
      ]),
      None,
      span,
    ),
    @value.Value::String("found"),
  )
  assert_eq(
    env_value(
      host,
      "env",
      @value.Value::String("MISSING"),
      Some(@value.Value::String("fallback")),
      span,
    ),
    @value.Value::String("fallback"),
  )
  for
    arguments in [
      [@value.Value::String("bad"), @value.Value::String("abc")],
      [@value.Value::String("-1"), @value.Value::String("abc")],
      [@value.Value::String("1"), @value.Value::String("")],
      [@value.Value::String("1"), @value.Value::String("aba")],
    ] {
    try choose_value(host, arguments, span) catch {
      Builtin(Failure(..), ..) => ()
      error => fail("unexpected choose error: \{Repr(error)}")
    } noraise {
      _ => fail("expected choose validation error")
    }
  }
  for
    style in [
      "dim", "italic", "underline", "blink", "reverse", "hidden", "strikethrough",
      "black", "green", "yellow", "magenta", "cyan", "white", "bg:red", "fg:blue",
    ] {
    assert_true(style_code(style) is Some(_))
  }
  assert_eq(which_value(host, "", EvaluationContext::new(cwd~), span), "")
}

///|
test "evaluator context failures cover missing and list-specific facts" {
  let span = evaluator_coverage_span()
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let lists = EvaluationContext::new(cwd~, lists=true, environment=[])
  let plain = EvaluationContext::new(cwd~, environment=[])
  assert_eq(
    context_builtin("bool", [@value.Value::List([])], lists, span),
    Some(@value.Value::List([])),
  )
  for
    row in [
      (
        "bool",
        [
          @value.Value::List([
            @value.Value::String("true"),
            @value.Value::String("false"),
          ]),
        ],
        lists,
      ),
      ("show", [@value.Value::String("value")], plain),
      ("join_list", [@value.Value::List([])], plain),
      ("num_jobs", [], plain),
      ("runtime_directory", [], lists),
      ("executable_directory", [], lists),
      ("recipe_name", [], lists),
    ] {
    let (name, arguments, context) = row
    try context_builtin(name, arguments, context, span) catch {
      Builtin(_, ..) => ()
      error => fail("unexpected context error for \{name}: \{Repr(error)}")
    } noraise {
      _ => fail("expected context error for \{name}")
    }
  }
  assert_eq(
    context_builtin("quote", [@value.Value::String("a b")], plain, span),
    Some(@value.Value::String("'a b'")),
  )
  assert_eq(
    context_builtin(
      "quote",
      [@value.Value::List([@value.Value::String("a b")])],
      lists,
      span,
    ),
    Some(@value.Value::String("'a b'")),
  )
  assert_eq(context_builtin("join", [], lists, span), None)
  assert_eq(
    context_builtin("num_jobs", [], lists, span),
    Some(@value.Value::List([])),
  )
  try
    context_parent("root", Some(try! @path.PathValue::new("/", Unix)), span)
  catch {
    MissingContext(fact="root parent", ..) => ()
    error => fail("unexpected root parent error: \{Repr(error)}")
  } noraise {
    _ => fail("expected root parent to be missing")
  }
  for
    argument in [
      @value.Value::List([]),
      @value.Value::String("MISSING"),
      @value.Value::List([
        @value.Value::String("FIRST"),
        @value.Value::String("SECOND"),
      ]),
    ] {
    try context_builtin("env_var", [argument], lists, span) catch {
      Builtin(Failure(message~), ..) =>
        assert_true(
          message.contains("not present") || message.contains("empty"),
        )
      error => fail("unexpected environment context error: \{Repr(error)}")
    } noraise {
      _ => fail("expected missing environment context")
    }
  }
}

///|
test "non-process effects cover deterministic filesystem and host facts" {
  let span = evaluator_coverage_span()
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  host.set_env("MODE", "test")
  host.set_clock_millis(1000L)
  host.set_random_stream(
    Bytes::from_array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]),
  )
  let file = try! @path.PathValue::new("/workspace/input.txt", Unix)
  host.put_file(file, b"contents")
  let context = EvaluationContext::new(cwd~, lists=true, utc_offset_seconds=0)
  let call = fn(name : String, arguments : Array[@value.Value]) raise {
    call_non_process_effect_with_context(host, name, arguments, context, span)
  }
  assert_eq(call("arch", []), @value.Value::String("x86_64"))
  assert_eq(call("os", []), @value.Value::String("linux"))
  assert_eq(call("os_family", []), @value.Value::String("unix"))
  assert_eq(
    call("env", [@value.Value::String("MODE")]),
    @value.Value::String("test"),
  )
  assert_eq(
    call("read", [@value.Value::String("input.txt")]),
    @value.Value::String("contents"),
  )
  assert_true(
    call("canonicalize", [@value.Value::String("input.txt")])
    .to_string()
    .contains("input.txt"),
  )
  assert_eq(
    call("path_exists", [@value.Value::String("")]),
    @value.Value::List([]),
  )
  assert_eq(
    call("path_exists", [@value.Value::String("input.txt")]),
    @value.Value::String("true"),
  )
  assert_eq(
    call("write", [
      @value.Value::String("output.txt"),
      @value.Value::String("written"),
    ]),
    @value.Value::String(""),
  )
  assert_eq(
    call("read", [@value.Value::String("output.txt")]),
    @value.Value::String("written"),
  )
  assert_eq(call("now_millis", []), @value.Value::String("1000"))
  assert_true(
    call("datetime_utc", [@value.Value::String("%s")]).to_string().length() > 0,
  )
  assert_true(
    call("sha256_file", [@value.Value::String("input.txt")])
    .to_string()
    .length() >
    0,
  )
  assert_true(
    call("blake3_file", [@value.Value::String("input.txt")])
    .to_string()
    .length() >
    0,
  )
  assert_true(call("uuid", []).to_string().contains("-"))
  try call("shell", [@value.Value::String("echo ok")]) catch {
    EffectRequired(effect="process", ..) => ()
    error => fail("unexpected shell effect error: \{Repr(error)}")
  } noraise {
    _ => fail("expected process effect requirement")
  }
  try call("require", [@value.Value::String("missing-tool")]) catch {
    Builtin(Failure(message~), ..) =>
      assert_true(message.contains("missing-tool"))
    error => fail("unexpected require error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing executable")
  }
}

///|
test "non-process effects map denied capabilities and platform variants" {
  let span = evaluator_coverage_span()
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let context = EvaluationContext::new(cwd~, lists=true, utc_offset_seconds=0)
  let plain = EvaluationContext::new(cwd~)

  for
    platform in [
      @host.PlatformInfo::new(Macos, "aarch64", Unix),
      @host.PlatformInfo::new(Other("freebsd"), "x86_64", Unix),
    ] {
    let host = @host.FakeHost::new(cwd, platform)
    assert_true(
      call_non_process_effect_with_context(host, "os", [], context, span)
      .to_string()
      .length() >
      0,
    )
  }
  let windows_cwd = try! @path.PathValue::new("C:\\workspace", Windows)
  let windows = @host.FakeHost::new(
    windows_cwd,
    @host.PlatformInfo::new(Windows, "x86_64", Windows),
  )
  assert_eq(
    call_non_process_effect_with_context(
      windows,
      "os",
      [],
      EvaluationContext::new(cwd=windows_cwd, lists=true),
      span,
    ),
    @value.Value::String("windows"),
  )

  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  assert_eq(
    call_non_process_effect_with_context(
      host,
      "just_version",
      [],
      context,
      span,
    ),
    @value.Value::String("1.57.0"),
  )
  assert_eq(
    call_non_process_effect_with_context(
      host,
      "absolute_path",
      [
        @value.Value::List([
          @value.Value::String("a"),
          @value.Value::String("b"),
        ]),
      ],
      context,
      span,
    ),
    @value.Value::List([
      @value.Value::String("/workspace/a"),
      @value.Value::String("/workspace/b"),
    ]),
  )
  assert_eq(
    call_non_process_effect_with_context(
      host,
      "absolute_path",
      [@value.Value::String("a")],
      plain,
      span,
    ),
    @value.Value::String("/workspace/a"),
  )
  try
    call_non_process_effect_with_context(
      host,
      "which",
      [@value.Value::String("tool")],
      plain,
      span,
    )
  catch {
    Builtin(Failure(message~), ..) => assert_true(message.contains("set lists"))
    error => fail("unexpected which mode error: \{Repr(error)}")
  } noraise {
    _ => fail("expected which list-mode failure")
  }

  let denied_read = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  denied_read.deny(@host.FsRead)
  for name in ["canonicalize", "read", "sha256_file", "blake3_file"] {
    try
      call_non_process_effect_with_context(
        denied_read,
        name,
        [@value.Value::String("missing")],
        context,
        span,
      )
    catch {
      Host(_, ..) | Builtin(_, ..) => ()
      error => fail("unexpected denied \{name} error: \{Repr(error)}")
    } noraise {
      _ => fail("expected denied \{name}")
    }
  }
  let denied_write = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  denied_write.deny(@host.FsWrite)
  try
    call_non_process_effect_with_context(
      denied_write,
      "write",
      [@value.Value::String("output"), @value.Value::String("value")],
      context,
      span,
    )
  catch {
    Host(_, ..) => ()
    error => fail("unexpected denied write error: \{Repr(error)}")
  } noraise {
    _ => fail("expected denied write")
  }
  let denied_clock = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  denied_clock.deny(@host.Clock)
  for
    row in [("now_millis", []), ("datetime_utc", [@value.Value::String("%s")])] {
    try
      call_non_process_effect_with_context(
        denied_clock,
        row.0,
        row.1,
        context,
        span,
      )
    catch {
      Host(_, ..) => ()
      error => fail("unexpected denied clock error: \{Repr(error)}")
    } noraise {
      _ => fail("expected denied clock")
    }
  }
  let denied_random = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  denied_random.deny(@host.Random)
  try
    call_non_process_effect_with_context(
      denied_random,
      "uuid",
      [],
      context,
      span,
    )
  catch {
    Host(_, ..) => ()
    error => fail("unexpected denied random error: \{Repr(error)}")
  } noraise {
    _ => fail("expected denied random")
  }
  let short_random = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  short_random.set_random_stream(b"short")
  try
    call_non_process_effect_with_context(
      short_random,
      "uuid",
      [],
      context,
      span,
    )
  catch {
    Host(RandomExhausted(requested=16, remaining=5), ..) => ()
    Builtin(Failure(message~), ..) =>
      assert_true(message.contains("byte count"))
    error => fail("unexpected short random error: \{Repr(error)}")
  } noraise {
    _ => fail("expected short random stream")
  }
}
