///|
fn loader_behavior_host() -> @host.FakeHost {
  @host.FakeHost::new(
    try! @path.PathValue::new("/workspace", Unix),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
}

///|
test "loader whitebox behavior visits path and candidate helpers" {
  let root = try! @path.PathValue::new("/workspace/project", Unix)
  let parent = try! @path.PathValue::new("/workspace", Unix)
  assert_eq(source_directory(root), parent)
  assert_true(path_is_within(parent, root))
  assert_true(path_is_within(parent, parent))
  assert_false(path_is_within(root, parent))
  assert_eq(parent_or_self(root), Some(parent))
  assert_eq(parent_or_self(parent), Some(try! @path.PathValue::new("/", Unix)))
  assert_eq(lower_ascii("AbC-XYZ"), "abc-xyz")
  assert_true(filename_lexical_compare("a", "b") < 0)
  assert_true(filename_lexical_compare("b", "a") > 0)
  assert_eq(filename_lexical_compare("same", "same"), 0)

  let host = loader_behavior_host()
  let file = try! @path.PathValue::new("/workspace/tool.just", Unix)
  host.put_file(file, b"tool:\n")
  let candidates : Array[@path.PathValue] = []
  try! push_existing_module_candidate(host, candidates, file)
  try! push_existing_module_candidate(host, candidates, file)
  assert_eq(candidates.length(), 1)
  let directory = try! @path.PathValue::new("/workspace/tools", Unix)
  let nested = directory.join(try! @path.PathValue::new("justfile", Unix))
  host.put_file(nested, b"nested:\n")
  try! push_module_directory_candidates(host, candidates, directory)
  assert_eq(candidates.length(), 2)
}

///|
test "loader whitebox behavior resolves explicit and implicit modules" {
  let source = @source.Source::from_text(
    @source.SourceId::new(9600),
    "module.just",
    "mod explicit 'modules/explicit.just'\nmod implicit\n",
  )
  let ast = try! @parser.parse(source)
  let host = loader_behavior_host()
  let root = try! @path.PathValue::new("/workspace/module.just", Unix)
  let explicit_path = try! @path.PathValue::new(
    "/workspace/modules/explicit.just",
    Unix,
  )
  host.put_file(explicit_path, b"explicit:\n")
  let implicit_path = try! @path.PathValue::new(
    "/workspace/implicit.just",
    Unix,
  )
  host.put_file(implicit_path, b"implicit:\n")
  for item in ast.items() {
    guard item is Module(module_definition) else { continue }
    let resolved = resolve_module_file(host, root, module_definition)
    assert_true(resolved is Some(_))
  }
  let optional = @syntax.Module::new(
    "missing",
    source.full_span(),
    None,
    true,
    source.full_span(),
  )
  assert_eq(resolve_module_file(host, root, optional), None)
  let imported = @syntax.StringLiteral::new(
    "\"~/common.just\"",
    "~/common.just",
    Cooked,
    source.full_span(),
  )
  assert_eq(
    import_path(root, imported, environment=[("HOME", "/home/test")]).as_string(),
    "/home/test/common.just",
  )

  let directory_source = @source.Source::from_text(
    @source.SourceId::new(9604),
    "directory-module.just",
    "mod directory 'modules/directory'\n",
  )
  let directory_ast = try! @parser.parse(directory_source)
  let directory_module = try! @path.PathValue::new(
    "/workspace/modules/directory/mod.just",
    Unix,
  )
  host.put_file(directory_module, b"nested:\n")
  for item in directory_ast.items() {
    guard item is Module(definition) else { continue }
    assert_eq(
      resolve_module_file(host, root, definition),
      Some(directory_module),
    )
  }
}

///|
test "loader whitebox behavior visits candidate filtering and missing modules" {
  let host = loader_behavior_host()
  let directory = try! @path.PathValue::new("/workspace", Unix)
  let plain = directory.join(try! @path.PathValue::new("tools", Unix))
  host.put_file(plain, b"not a directory\n")
  let candidates : Array[@path.PathValue] = []
  try! push_existing_module_candidate(host, candidates, plain)
  assert_eq(candidates.length(), 1)
  let missing_directory = directory.join(
    try! @path.PathValue::new("missing", Unix),
  )
  try! push_module_directory_candidates(host, candidates, missing_directory)
  let source = @source.Source::from_text(
    @source.SourceId::new(9601),
    "module-missing.just",
    "mod optional\nmod required\n",
  )
  let ast = try! @parser.parse(source)
  let root = directory.join(
    try! @path.PathValue::new("module-missing.just", Unix),
  )
  for item in ast.items() {
    guard item is Module(definition) else { continue }
    if definition.optional() {
      assert_eq(resolve_module_file(host, root, definition), None)
    } else {
      try resolve_module_file(host, root, definition) catch {
        ModuleFileMissing(..) => ()
        error => fail("unexpected missing module error: \{Repr(error)}")
      } noraise {
        _ => fail("expected missing module error")
      }
    }
  }
}

///|
async test "loader whitebox behavior visits async platform skips and host errors" {
  let host = loader_behavior_host()
  let root = try! @path.PathValue::new("/workspace/async.just", Unix)
  host.put_file(
    root, b"[windows]\nimport 'missing.just'\n[linux]\nimport? 'optional.just'\nroot:\n",
  )
  let graph = try! load_graph_async(
    host,
    root,
    @source.SourceId::new(9602),
    platform=@semantic.TargetPlatform::new(Linux, true),
  )
  assert_eq(graph.files().length(), 1)
  host.deny(FsRead)
  try load_async(host, root, @source.SourceId::new(9603)) catch {
    Host(CapabilityDenied(FsRead)) => ()
    error => fail("unexpected async host error: \{Repr(error)}")
  } noraise {
    _ => fail("expected async host error")
  }
}

///|
async test "loader whitebox behavior traverses async imports and modules" {
  let host = loader_behavior_host()
  let root = try! @path.PathValue::new("/workspace/async-graph.just", Unix)
  let imported = try! @path.PathValue::new("/workspace/imported.just", Unix)
  let module_file = try! @path.PathValue::new("/workspace/tools.just", Unix)
  host.put_file(root, b"import 'imported.just'\nmod tools\nroot:\n")
  host.put_file(imported, b"imported:\n")
  host.put_file(module_file, b"tool:\n")
  let graph = try! load_graph_async(
    host,
    root,
    @source.SourceId::new(9610),
    platform=@semantic.TargetPlatform::new(Linux, true),
  )
  assert_eq(graph.files().length(), 3)
  assert_eq(graph.files()[0].relation(), RootSource)
  assert_eq(graph.files()[1].relation(), ImportedSource)
  assert_eq(graph.files()[2].relation(), ModuleSource)
  assert_eq(graph.files()[2].module_path().as_string(), "tools")
  let stdin_graph = try! load_stdin_graph_async(
    host,
    b"import 'imported.just'\nroot:\n",
    @source.SourceId::new(9620),
    try! @path.PathValue::new("/workspace", Unix),
  )
  assert_eq(stdin_graph.files().length(), 2)
}

///|
test "loader whitebox behavior exercises source metadata and home routing" {
  let stdin = try! load_stdin(
    b"root:\n",
    @source.SourceId::new(9703),
    display_name="<memory>",
  )
  assert_eq(stdin.relation(), RootSource)
  assert_eq(stdin.parent(), None)
  assert_eq(stdin.module_path().as_string(), "")
  assert_eq(stdin.module_directory().as_string(), ".")
  let plain = try! load_bytes(
    b"root:\n",
    @source.SourceId::new(9704),
    "nested/justfile",
  )
  assert_eq(plain.path().as_string(), "nested/justfile")
  assert_eq(plain.module_directory().as_string(), "nested")
  let markdown = try! load_markdown(
    b"before\n```just\nfrom_md:\n```\n",
    @source.SourceId::new(9705),
    display_name="README.MD",
  )
  assert_true(markdown.source().length() > 0)
  assert_true(is_markdown_path(markdown.path()))

  let host = loader_behavior_host()
  let candidate = try! @path.PathValue::new("/workspace/candidate.just", Unix)
  host.put_file(candidate, b"candidate:\n")
  let candidates : Array[@path.PathValue] = []
  try! push_existing_module_candidate(host, candidates, candidate)
  try! push_existing_module_candidate(host, candidates, candidate)
  assert_eq(candidates.length(), 1)
  let missing = try! @path.PathValue::new("/workspace/missing.just", Unix)
  try! push_existing_module_candidate(host, candidates, missing)
  assert_eq(candidates.length(), 1)
  let span = @source.Span::new(@source.SourceId::new(9706), 0, 1)
  let windows_parent = try! @path.PathValue::new(
    "C:\\project\\justfile",
    Windows,
  )
  let literal = @syntax.StringLiteral::new(
    "\"~\\\\common.just\"",
    "~\\common.just",
    Cooked,
    span,
  )
  assert_eq(
    import_path(windows_parent, literal, environment=[
      ("USERPROFILE", "C:\\Users\\tester"),
    ]).as_string(),
    "C:\\Users\\tester\\common.just",
  )
}

///|
test "loader whitebox behavior rejects invalid sources and incompatible paths" {
  let unix = try! @path.PathValue::new("/workspace", Unix)
  let windows = try! @path.PathValue::new("C:\\workspace", Windows)
  assert_false(path_is_within(unix, windows))
  let invalid = Bytes::from_array([0xff])
  try load_stdin(invalid, @source.SourceId::new(9710)) catch {
    InvalidSource(_) => ()
    error => fail("unexpected invalid stdin error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid stdin source")
  }
  try load_bytes(invalid, @source.SourceId::new(9711), "invalid.just") catch {
    InvalidSource(_) => ()
    error => fail("unexpected invalid source error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid source bytes")
  }
  try load_markdown(invalid, @source.SourceId::new(9712)) catch {
    InvalidSource(_) => ()
    error => fail("unexpected invalid Markdown error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid Markdown source")
  }

  let host = loader_behavior_host()
  let plain = try! @path.PathValue::new("/workspace/plain", Unix)
  host.put_file(plain, b"not a directory\n")
  let candidates : Array[@path.PathValue] = []
  try! push_module_directory_candidates(host, candidates, plain)
  assert_eq(candidates, [])
}

///|
async test "loader whitebox behavior maps async parse sources and optional imports" {
  let host = loader_behavior_host()
  let invalid = try! @path.PathValue::new("/workspace/invalid.just", Unix)
  host.put_file(invalid, b"run: (\n")
  try load_async(host, invalid, @source.SourceId::new(9720)) catch {
    ParseSource(_, source_name~, source_bytes~) => {
      assert_eq(source_name, "/workspace/invalid.just")
      assert_eq(source_bytes, b"run: (\n")
    }
    error => fail("unexpected async parse source error: \{Repr(error)}")
  } noraise {
    _ => fail("expected async parse failure")
  }

  let root = try! @path.PathValue::new("/workspace/optional.just", Unix)
  host.put_file(root, b"import? 'missing.just'\nroot:\n")
  let graph = try! load_graph_async(host, root, @source.SourceId::new(9721))
  assert_eq(graph.files().length(), 1)
}

///|
test "loader whitebox behavior maps denied source and environment access" {
  let path = try! @path.PathValue::new("/workspace/denied.just", Unix)
  let filesystem = loader_behavior_host()
  filesystem.deny(FsRead)
  try load(filesystem, path, @source.SourceId::new(9730)) catch {
    Host(CapabilityDenied(FsRead)) => ()
    error => fail("unexpected denied source error: \{Repr(error)}")
  } noraise {
    _ => fail("expected denied source read")
  }

  let environment = loader_behavior_host()
  environment.deny(Environment)
  try load_from_current_dir(environment, @source.SourceId::new(9731)) catch {
    Host(CapabilityDenied(Environment)) => ()
    error => fail("unexpected denied environment error: \{Repr(error)}")
  } noraise {
    _ => fail("expected denied current directory")
  }
}
