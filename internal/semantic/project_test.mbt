///|
test "project compilation keeps root and module scopes independent" {
  let root_source = @source.Source::from_text(
    @source.SourceId::new(901),
    "root.just",
    "value := 'root'\nroot:\n",
  )
  let child_source = @source.Source::from_text(
    @source.SourceId::new(902),
    "child.just",
    "value := 'child'\nchild:\n",
  )
  let root_compilation = try! compile(try! @parser.parse(root_source))
  let child_compilation = try! compile(try! @parser.parse(child_source))
  let child_path = try! @modulepath.ModulePath::parse("tools")
  let project = try! ProjectCompilation::new([
    ProjectModule::new(
      @modulepath.ModulePath::root(),
      root_compilation,
      try! @path.PathValue::new("/workspace", Unix),
    ),
    ProjectModule::new(
      child_path,
      child_compilation,
      try! @path.PathValue::new("/workspace/tools", Unix),
    ),
  ])
  assert_eq(project.module_paths(), [@modulepath.ModulePath::root(), child_path])
  assert_eq(project.root().variable_names(), ["value"])
  assert_eq(project.root().recipe_names(), ["root"])
  assert_eq(project.module_compilation(child_path).unwrap().recipe_names(), [
    "child",
  ])
  assert_eq(
    project.directory(child_path),
    Some(try! @path.PathValue::new("/workspace/tools", Unix)),
  )
}

///|
test "project compilation exposes metadata, defaults, and resolution failures" {
  let root_path = @modulepath.ModulePath::root()
  let tools_path = try! @modulepath.ModulePath::parse("tools")
  let missing_path = try! @modulepath.ModulePath::parse("missing")
  let root_source = @source.Source::from_text(
    @source.SourceId::new(910),
    "root.just",
    "alias local := root\nroot:\n",
  )
  let tools_source = @source.Source::from_text(
    @source.SourceId::new(911),
    "tools.just",
    "[default]\nbuild:\n",
  )
  let root_compilation = try! compile(try! @parser.parse(root_source))
  let tools_compilation = try! compile(try! @parser.parse(tools_source))
  let root_file = try! @path.PathValue::new("/workspace/justfile", Unix)
  let tools_file = try! @path.PathValue::new("/workspace/tools.just", Unix)
  let project = try! ProjectCompilation::new(
    [
      ProjectModule::new(
        root_path,
        root_compilation,
        try! @path.PathValue::new("/workspace", Unix),
        source_file=root_file,
        source_files=[(root_source.id(), root_file)],
        declaration_doc="root docs",
        default_recipe="root",
      ),
      ProjectModule::new(
        tools_path,
        tools_compilation,
        try! @path.PathValue::new("/workspace/tools", Unix),
        source_file=tools_file,
        source_files=[(tools_source.id(), tools_file)],
      ),
    ],
    absent_modules=[missing_path],
  )
  assert_eq(project.modules().length(), 2)
  assert_eq(project.source_file(root_path), Some(root_file))
  assert_eq(project.source_files(tools_path).length(), 1)
  assert_eq(project.module_declaration_doc(root_path), Some("root docs"))
  assert_eq(project.default_recipe(root_path), Some("root"))
  assert_eq(project.default_recipe(tools_path), None)
  assert_true(project.is_absent_module(missing_path))
  assert_eq(
    project.absent_module_for_reference(root_path, "missing"),
    Some(missing_path),
  )
  assert_eq(project.resolve_module(root_path, "tools"), Some(tools_path))
  assert_eq(project.resolve_module(root_path, "unknown"), None)
  guard project.resolve_recipe(root_path, "local") is Some(recipe) else {
    fail("expected alias recipe resolution")
  }
  assert_eq(recipe.recipe_name(), "root")
  assert_eq(
    project.resolve_recipe(tools_path, "build").unwrap().module_path(),
    tools_path,
  )
  assert_eq(project.resolve_recipe(root_path, "unknown"), None)
  assert_eq(project.recipe_absent_modules(root_path, "root"), [])
  assert_eq(project.alias_absent_modules(root_path, "local"), [])

  try ProjectCompilation::new([]) catch {
    MissingRootModule => ()
    error => fail("unexpected missing root error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing root error")
  }
  try
    ProjectCompilation::new([
      ProjectModule::new(
        root_path,
        root_compilation,
        try! @path.PathValue::new("/workspace", Unix),
      ),
      ProjectModule::new(
        root_path,
        root_compilation,
        try! @path.PathValue::new("/workspace", Unix),
      ),
    ])
  catch {
    DuplicateModulePath(_) => ()
    error => fail("unexpected duplicate module error: \{Repr(error)}")
  } noraise {
    _ => fail("expected duplicate module error")
  }
}

///|
test "project compilation accessors cover missing and inferred metadata" {
  let root_path = @modulepath.ModulePath::root()
  let child_path = try! @modulepath.ModulePath::parse("child")
  let missing_path = try! @modulepath.ModulePath::parse("missing")
  let source = @source.Source::from_text(
    @source.SourceId::new(912),
    "root.just",
    "[default]\nfirst:\nsecond:\n",
  )
  let compilation = try! compile(try! @parser.parse(source))
  let directory = try! @path.PathValue::new("/workspace", Unix)
  let file = try! @path.PathValue::new("/workspace/root.just", Unix)
  let project_module = ProjectModule::new(
    root_path,
    compilation,
    directory,
    source_file=file,
    source_files=[(source.id(), file)],
    declaration_doc="docs",
  )
  assert_eq(project_module.module_path(), root_path)
  assert_eq(project_module.compilation().recipe_names(), ["first", "second"])
  assert_eq(project_module.directory(), directory)
  assert_eq(project_module.source_file(), Some(file))
  assert_eq(project_module.source_files(), [(source.id(), file)])
  assert_eq(project_module.declaration_attributes(), [])
  assert_eq(project_module.declaration_doc(), Some("docs"))
  assert_eq(project_module.default_recipe(), None)
  let project = try! ProjectCompilation::new(
    [ProjectModule::new(root_path, compilation, directory)],
    absent_modules=[missing_path],
  )
  assert_eq(project.default_recipe(root_path), Some("first"))
  assert_true(project.module_compilation(child_path) is None)
  assert_eq(project.directory(child_path), None)
  assert_eq(project.source_file(child_path), None)
  assert_eq(project.source_files(child_path), [])
  assert_eq(project.module_declaration_attributes(child_path), [])
  assert_eq(project.module_declaration_doc(child_path), None)
  assert_eq(project.default_recipe(child_path), None)
  assert_false(project.recipe_disabled(root_path, "first"))
  assert_false(project.alias_disabled(root_path, "alias"))
  assert_eq(project.resolve_module(child_path, "unknown"), None)
  assert_eq(project.resolve_recipe(child_path, "unknown"), None)
  assert_eq(
    project.absent_module_for_reference(root_path, "missing"),
    Some(missing_path),
  )
  assert_eq(
    project.absent_module_for_reference(root_path, "invalid name"),
    None,
  )
  assert_eq(project.resolve_module(root_path, "invalid name"), None)
}

///|
test "project validation propagates absent modules through recipes and aliases" {
  let root_path = @modulepath.ModulePath::root()
  let missing_path = try! @modulepath.ModulePath::parse("missing")
  let source = @source.Source::from_text(
    @source.SourceId::new(913),
    "root.just",
    "mod? missing\nroot: missing::build\nalias indirect := root\n",
  )
  let ast = try @parser.parse(source) catch {
    error => fail("project coverage parse failed: \{Repr(error)}")
  } noraise {
    value => value
  }
  let compilation = try compile(ast, defer_recipe_linking=true) catch {
    error => fail("project coverage compile failed: \{Repr(error)}")
  } noraise {
    value => value
  }
  let project = try
    ProjectCompilation::new(
      [
        ProjectModule::new(
          root_path,
          compilation,
          try! @path.PathValue::new("/workspace", Unix),
        ),
      ],
      absent_modules=[missing_path],
    )
  catch {
    error => fail("project coverage construction failed: \{Repr(error)}")
  } noraise {
    value => value
  }
  try validate_project_compilation(project) catch {
    error => fail("project coverage validation failed: \{Repr(error)}")
  } noraise {
    _ => ()
  }
  assert_true(project.recipe_disabled(root_path, "root"))
  assert_true(project.alias_disabled(root_path, "indirect"))
  assert_eq(project.recipe_absent_modules(root_path, "root"), [missing_path])
  assert_eq(project.alias_absent_modules(root_path, "indirect"), [missing_path])
  assert_eq(project.absent_module_for_reference(root_path, "indirect"), None)
}
