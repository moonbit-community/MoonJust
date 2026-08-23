///|
fn unix(value : String) -> @path.PathValue raise @path.PathError {
  @path.PathValue::new(value, Unix)
}

///|
test "explicit input paths resolve from the invocation directory" {
  let model = try! WorkingDirectoryModel::from_justfile(
    unix("/workspace/invocation"),
    unix("../config/justfile"),
  )
  assert_eq(model.invocation_directory(), unix("/workspace/invocation"))
  assert_eq(model.project_directory(), unix("/workspace/config"))
  assert_eq(model.module_directory(), unix("/workspace/config"))
  let overridden = try! WorkingDirectoryModel::from_justfile(
    unix("/workspace/invocation"),
    unix("../config/justfile"),
    working_directory=Some(unix("../run")),
  )
  assert_eq(overridden.project_directory(), unix("/workspace/run"))
}

///|
test "stdin uses invocation or explicit working directory" {
  let invocation = unix("/workspace/invocation")
  assert_eq(
    (try! WorkingDirectoryModel::from_stdin(invocation)).project_directory(),
    invocation,
  )
  assert_eq(
    (try! WorkingDirectoryModel::from_stdin(
      invocation,
      working_directory=Some(unix("../run")),
    )).project_directory(),
    unix("/workspace/run"),
  )
}

///|
test "symlink display parent remains distinct from canonical identity" {
  let model = try! WorkingDirectoryModel::from_justfile(
    unix("/workspace/links/sub"),
    unix("../justfile"),
  )
  assert_eq(model.project_directory(), unix("/workspace/links"))
  assert_false(model.project_directory() == unix("/workspace/sources"))
}

///|
test "imports retain module directory and modules establish their own" {
  let root = try! WorkingDirectoryModel::from_justfile(
    unix("/workspace/invocation"),
    unix("../justfile"),
  )
  let imported = root.for_import(unix("/workspace/includes/tasks.just"))
  assert_eq(imported.module_directory(), unix("/workspace"))
  let child_module = try! root.for_module(unix("modules/release/mod.just"))
  assert_eq(child_module.project_directory(), unix("/workspace"))
  assert_eq(child_module.module_directory(), unix("/workspace/modules/release"))
}

///|
test "module setting controls evaluation and default recipe cwd" {
  let model = try! WorkingDirectoryModel::from_justfile(
    unix("/workspace/invocation"),
    unix("../justfile"),
  )
  assert_eq(
    try! model.evaluation_directory(module_setting=Some("build")),
    unix("/workspace/build"),
  )
  assert_eq(
    try! model.recipe_directory(module_setting=Some("build")),
    unix("/workspace/build"),
  )
}

///|
test "no-cd only redirects recipe execution to invocation cwd" {
  let model = try! WorkingDirectoryModel::from_justfile(
    unix("/workspace/invocation"),
    unix("../justfile"),
  )
  assert_eq(
    try! model.evaluation_directory(module_setting=Some("build")),
    unix("/workspace/build"),
  )
  assert_eq(
    try! model.recipe_directory(module_setting=Some("build"), module_no_cd=true),
    unix("/workspace/invocation"),
  )
  assert_eq(
    try! model.recipe_directory(recipe_no_cd=true),
    unix("/workspace/invocation"),
  )
}

///|
test "recipe working-directory overrides settings and no-cd" {
  let model = try! WorkingDirectoryModel::from_justfile(
    unix("/workspace/invocation"),
    unix("../justfile"),
  )
  assert_eq(
    try! model.recipe_directory(
      module_setting=Some("build"),
      module_no_cd=true,
      recipe_working_directory=Some("release"),
    ),
    unix("/workspace/build/release"),
  )
  assert_eq(
    try! model.recipe_directory(
      recipe_no_cd=true,
      recipe_working_directory=Some("release"),
    ),
    unix("/workspace/release"),
  )
}

///|
test "absolute working directories replace their lexical base" {
  let model = try! WorkingDirectoryModel::from_justfile(
    unix("/workspace/invocation"),
    unix("../justfile"),
  )
  assert_eq(
    try! model.recipe_directory(
      module_setting=Some("/srv/build"),
      recipe_working_directory=Some("/tmp/release"),
    ),
    unix("/tmp/release"),
  )
}

///|
test "Unix and Windows path flavors cannot be mixed" {
  try
    WorkingDirectoryModel::from_justfile(
      unix("/workspace"),
      @path.PathValue::new("C:\\justfile", Windows),
    )
  catch {
    WorkingDirectoryError::Path(_) => ()
    error => fail("unexpected working-directory error: \{Repr(error)}")
  } noraise {
    _ => fail("expected path flavor mismatch")
  }
}

///|
test "justfile root is rejected even with a working-directory override" {
  try
    WorkingDirectoryModel::from_justfile(
      unix("/workspace"),
      unix("/"),
      working_directory=Some(unix("/run")),
    )
  catch {
    WorkingDirectoryError::JustfileWithoutParent(path) =>
      assert_eq(path, unix("/"))
    error => fail("unexpected parent error: \{Repr(error)}")
  } noraise {
    _ => fail("expected parentless justfile failure")
  }
}

///|
test "global justfile keeps configuration source separate from project cwd" {
  let model = WorkingDirectoryModel::from_global_justfile(
    unix("/workspace/repo/sub"),
    unix("/home/test/.config/just/justfile"),
    unix("/workspace/repo"),
  )
  assert_eq(model.invocation_directory(), unix("/workspace/repo/sub"))
  assert_eq(model.project_directory(), unix("/workspace/repo"))
  assert_eq(model.module_directory(), unix("/workspace/repo"))
  assert_eq(model.justfile(), Some(unix("/home/test/.config/just/justfile")))
}
