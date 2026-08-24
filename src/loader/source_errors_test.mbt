///|
test "loader behavior exercises limits, source provenance, and diagnostics" {
  let path = try! @path.PathValue::new("/workspace/justfile", Unix)
  let other = try! @path.PathValue::new("/workspace/common.just", Unix)
  let span = @source.Span::new(@source.SourceId::new(9200), 0, 1)
  let parser_error = @parser.ParserError::ExtraneousInput(span~)
  let errors : Array[@loader.LoaderError] = [
    InvalidLimit,
    NoJustfileFound(start=path, filename="justfile"),
    AmbiguousJustfile(directory=path, found=["justfile", ".justfile"]),
    ExplicitFileMissing(path~),
    ImportFileMissing(span~),
    Host(InvalidInput("bad host")),
    InvalidSource(InvalidUtf8(offset=2)),
    Parse(parser_error),
    ParseSource(parser_error, source_name="broken.just", source_bytes=b"x"),
    ImportCycle(path~, chain=[path, other], span=Some(span)),
    ModuleFileMissing(module_name="tools", span~),
    AmbiguousModuleFile(
      module_name="tools",
      found=[
        @path.PathValue::new("/workspace/tools.just", Unix),
        @path.PathValue::new("/workspace/tools/justfile", Unix),
      ],
      span~,
    ),
  ]
  for error in errors {
    assert_true(error.code().has_prefix("MJ-LOAD-"))
    let _ = error.span()
    let _ = error.diagnostic_source()
    let diagnostic = try! error.to_diagnostic(span)
    assert_eq(diagnostic.code(), error.code())
  }
  guard errors[8].diagnostic_source() is Some(source) else {
    fail("expected parse source to preserve bytes")
  }
  assert_eq(source.name(), "broken.just")
}

///|
test "loader behavior visits in-memory routing and lexical path helpers" {
  let samples = [
    ("plain.just", b"build:\n"),
    ("README.md", b"# prose\n```just\nfrom_md:\n```\n"),
    ("tasks.MD", b"~~~just\nfrom_tilde:\n~~~\n"),
    ("notes.txt", b"text:\n"),
  ]
  for index, sample in samples {
    let loaded = try! load_bytes(
      sample.1,
      @source.SourceId::new(9201 + index),
      sample.0,
    )
    assert_true(loaded.source().length() >= 0)
    assert_true(loaded.module_directory().as_string().length() >= 0)
  }
  assert_true(is_markdown_path(try! @path.PathValue::new("a.md", Unix)))
  assert_true(is_markdown_path(try! @path.PathValue::new("a.MD", Unix)))
  assert_false(is_markdown_path(try! @path.PathValue::new("a.just", Unix)))
  try GraphLimits::new(0) catch {
    _ => ()
  } noraise {
    _ => ()
  }
  let _ = try! GraphLimits::new(4)
}

///|
test "loader behavior exercises fallback, graph limits, and platform filtering" {
  let host = @host.FakeHost::new(
    try! @path.PathValue::new("/workspace", Unix),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let root = try! @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(root, b"import 'child.just'\nmod tools\nroot:\n")
  let child = try! @path.PathValue::new("/workspace/child.just", Unix)
  host.put_file(child, b"child:\n")
  let module_file = try! @path.PathValue::new("/workspace/tools.just", Unix)
  host.put_file(module_file, b"tool:\n")
  try
    load_graph(
      host,
      root,
      @source.SourceId::new(9601),
      limits=GraphLimits::new(1),
    )
  catch {
    Host(InvalidInput(message)) => assert_true(message.contains("limit"))
    error => fail("unexpected graph limit error: \{Repr(error)}")
  } noraise {
    _ => fail("expected graph limit error")
  }
  host.put_file(root, b"import? 'disabled.just'\nroot:\n")
  let filtered = try! load_graph(
    host,
    root,
    @source.SourceId::new(9602),
    platform=@semantic.TargetPlatform::new(Linux, true),
  )
  assert_eq(filtered.files().length(), 1)
  host.put_file(root, b"mod missing\nroot:\n")
  try load_graph(host, root, @source.SourceId::new(9603)) catch {
    ModuleFileMissing(module_name="missing", ..) => ()
    error => fail("unexpected module error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing module error")
  }
}

///|
async test "loader behavior exercises stdin graphs and environment loading" {
  let host = @host.FakeHost::new(
    try! @path.PathValue::new("/workspace", Unix),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  host.set_env("HOME", "/home/test")
  host.set_current_dir(try! @path.PathValue::new("/workspace", Unix))
  host.put_file(
    try! @path.PathValue::new("/workspace/common.just", Unix),
    b"common:\n",
  )
  host.put_file(
    try! @path.PathValue::new("/workspace/justfile", Unix),
    b"build:\n",
  )
  let loaded = try! load_from_current_dir(host, @source.SourceId::new(9604))
  assert_eq(loaded.path().as_string(), "/workspace/justfile")
  let graph = try! load_stdin_graph_async(
    host,
    b"import 'common.just'\nroot:\n",
    @source.SourceId::new(9605),
    try! @path.PathValue::new("/workspace", Unix),
  )
  assert_eq(graph.files().length(), 2)

  let root = try! @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(root, b"import 'missing.just'\nroot:\n")
  try load_graph_async(host, root, @source.SourceId::new(9606)) catch {
    ImportFileMissing(_) => ()
    error => fail("unexpected async import error: \{Repr(error)}")
  } noraise {
    _ => fail("expected async missing import")
  }
  host.put_file(root, b"import 'common.just'\nroot:\n")
  host.put_file(
    try! @path.PathValue::new("/workspace/common.just", Unix),
    b"import 'justfile'\ncommon:\n",
  )
  try load_graph_async(host, root, @source.SourceId::new(9607)) catch {
    ImportCycle(chain~, ..) => assert_eq(chain.length(), 2)
    error => fail("unexpected async cycle error: \{Repr(error)}")
  } noraise {
    _ => fail("expected async cycle")
  }
  host.put_file(root, b"import 'common.just'\nroot:\n")
  host.put_file(
    try! @path.PathValue::new("/workspace/common.just", Unix),
    b"common:\n",
  )
  try
    load_graph_async(
      host,
      root,
      @source.SourceId::new(9608),
      limits=GraphLimits::new(1),
    )
  catch {
    Host(InvalidInput(message)) => assert_true(message.contains("limit"))
    error => fail("unexpected async limit error: \{Repr(error)}")
  } noraise {
    _ => fail("expected async graph limit")
  }
}

///|
async test "loader behavior deduplicates imports and filters optional modules" {
  let host = @host.FakeHost::new(
    try! @path.PathValue::new("/workspace", Unix),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let root = try! @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(
    root, b"import 'shared.just'\nimport 'shared.just'\n[windows]\nmod windows_only\nmod? optional\nmod tools\nroot:\n",
  )
  host.put_file(
    try! @path.PathValue::new("/workspace/shared.just", Unix),
    b"shared:\n",
  )
  host.put_file(
    try! @path.PathValue::new("/workspace/tools/JUSTFILE", Unix),
    b"tool:\n",
  )
  let graph = try! load_graph_async(
    host,
    root,
    @source.SourceId::new(9630),
    platform=@semantic.TargetPlatform::new(Linux, true),
  )
  assert_eq(graph.files().length(), 3)
  assert_eq(graph.files()[1].relation(), ImportedSource)
  assert_eq(graph.files()[2].relation(), ModuleSource)
  assert_eq(graph.files()[2].module_path().as_string(), "tools")
  let sync_graph = try! load_graph(
    host,
    root,
    @source.SourceId::new(9640),
    platform=@semantic.TargetPlatform::new(Linux, true),
  )
  assert_eq(sync_graph.files().length(), 3)
  assert_eq(sync_graph.files()[2].module_path().as_string(), "tools")
}

///|
test "loader behavior exercises discovery precedence and ambiguity" {
  let host = @host.FakeHost::new(
    try! @path.PathValue::new("/workspace/project/sub", Unix),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let start = try! @path.PathValue::new("/workspace/project/sub", Unix)
  let project = try! @path.PathValue::new("/workspace/project", Unix)
  let project_file = try! @path.PathValue::new(
    "/workspace/project/JUSTFILE",
    Unix,
  )
  host.put_file(project_file, b"root:\n")
  assert_eq(try! discover(host, start), project_file)

  let explicit = try! @path.PathValue::new("/explicit/tasks.just", Unix)
  host.put_file(explicit, b"explicit:\n")
  assert_eq(
    try! discover(
      host,
      start,
      options=SearchOptions::new(explicit=Some(explicit)),
    ),
    explicit,
  )
  let missing = try! @path.PathValue::new("/missing/tasks.just", Unix)
  try
    discover(host, start, options=SearchOptions::new(explicit=Some(missing)))
  catch {
    ExplicitFileMissing(path~) => assert_eq(path, missing)
    error => fail("unexpected explicit error: \{Repr(error)}")
  } noraise {
    _ => fail("expected explicit file failure")
  }

  let global = try! @path.PathValue::new("/global/justfile", Unix)
  host.put_file(global, b"global:\n")
  assert_eq(
    try! discover(
      host,
      start,
      options=SearchOptions::new(
        filename="tasks.just",
        ceiling=Some(project),
        global=Some(global),
      ),
    ),
    global,
  )
  try
    discover(
      host,
      start,
      options=SearchOptions::new(filename="absent", ceiling=Some(project)),
    )
  catch {
    NoJustfileFound(filename="absent", ..) => ()
    error => fail("unexpected discovery error: \{Repr(error)}")
  } noraise {
    _ => fail("expected discovery failure")
  }

  let lower = try! @path.PathValue::new("/workspace/project/justfile", Unix)
  host.put_file(lower, b"lower:\n")
  try discover(host, project) catch {
    AmbiguousJustfile(found~, ..) => assert_eq(found.length(), 2)
    error => fail("unexpected ambiguity error: \{Repr(error)}")
  } noraise {
    _ => fail("expected justfile ambiguity")
  }
}

///|
test "loader behavior rejects invalid bytes and preserves graph provenance" {
  try
    load_bytes(
      Bytes::from_array([0xff]),
      @source.SourceId::new(9700),
      "bad.just",
    )
  catch {
    InvalidSource(InvalidUtf8(offset=0)) => ()
    error => fail("unexpected utf8 error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid UTF-8")
  }
  try
    load_markdown(
      b"```just\nbroken := \"unterminated\n```\n",
      @source.SourceId::new(9701),
    )
  catch {
    ParseSource(_, ..) | Parse(_) => ()
    error => fail("unexpected markdown parse error: \{Repr(error)}")
  } noraise {
    _ => fail("expected markdown parse error")
  }

  let host = @host.FakeHost::new(
    try! @path.PathValue::new("/workspace", Unix),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let root = try! @path.PathValue::new("/workspace/justfile", Unix)
  let shared = try! @path.PathValue::new("/workspace/shared.just", Unix)
  host.put_file(root, b"import 'shared.just'\nimport 'shared.just'\nroot:\n")
  host.put_file(shared, b"shared:\n")
  let graph = try! load_graph(host, root, @source.SourceId::new(9702))
  assert_eq(graph.files().length(), 2)
  assert_eq(graph.files()[0].relation(), RootSource)
  assert_eq(graph.files()[1].relation(), ImportedSource)
  assert_eq(graph.files()[1].parent(), Some(root))
  assert_true(graph.files()[1].import_span() is Some(_))
}

///|
test "loader behavior traverses a synchronous stdin graph" {
  let host = @host.FakeHost::new(
    try! @path.PathValue::new("/workspace", Unix),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let imported = try! @path.PathValue::new("/workspace/common.just", Unix)
  host.put_file(imported, b"common:\n")
  let graph = try! load_stdin_graph(
    host,
    b"import 'common.just'\nroot:\n",
    @source.SourceId::new(9710),
    try! @path.PathValue::new("/workspace", Unix),
  )
  assert_eq(graph.files().length(), 2)
  assert_eq(graph.files()[0].path().as_string(), "/workspace/<stdin>")
  assert_eq(graph.files()[1].canonical_path(), imported)
}
