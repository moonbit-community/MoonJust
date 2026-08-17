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
