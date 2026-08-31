///|
fn which_case(
  executable : String,
  platform : @host.OperatingSystem,
  path_value : String,
  pathext : String?,
  files : Array[String],
) -> @value.Value raise EvaluationError {
  let cwd = try! @path.PathValue::new("/workspace", @path.Unix)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(platform, "test", @path.Unix),
  )
  host.set_env("PATH", path_value)
  match pathext {
    Some(value) => host.set_env("PATHEXT", value)
    None => ()
  }
  for file in files {
    host.put_file(
      try! cwd.join(try! @path.PathValue::new(file, @path.Unix)),
      b"",
    )
  }
  let context = EvaluationContext::new(cwd~, lists=true)
  call_non_process_effect_with_context(
    host,
    "which",
    [@value.Value::String(executable)],
    context,
    @source.Span::origin(@source.SourceId::new(928)),
  )
}

///|
fn require_case() -> @value.Value raise EvaluationError {
  let cwd = try! @path.PathValue::new("/workspace", @path.Unix)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(@host.OperatingSystem::Linux, "test", @path.Unix),
  )
  host.set_env("PATH", "/workspace")
  host.put_file(
    try! cwd.join(@path.PathValue::new("hello.exe", @path.Unix)),
    b"",
  )
  call_non_process_effect_with_context(
    host,
    "require",
    [@value.Value::String("hello.exe")],
    EvaluationContext::new(cwd~, lists=true),
    @source.Span::origin(@source.SourceId::new(930)),
  )
}

///|
test "upstream which_function::finds_executable" {
  let value = try! which_case(
    "hello.exe",
    @host.OperatingSystem::Linux,
    "/workspace",
    None,
    ["hello.exe"],
  )
  assert_eq(value.elements(), ["/workspace/hello.exe"])
}

///|
test "upstream which_function::finds_executable_via_pathext" {
  let value = try! which_case(
    "foo",
    @host.OperatingSystem::Windows,
    "/workspace",
    Some(".exe"),
    ["foo.exe"],
  )
  assert_eq(value.elements(), ["/workspace/foo.exe"])
}

///|
test "upstream which_function::supports_multiple_paths" {
  let value = try! which_case(
    "hello.exe",
    @host.OperatingSystem::Linux,
    "/missing:/workspace",
    None,
    ["hello.exe"],
  )
  assert_eq(value.elements(), ["/workspace/hello.exe"])
}

///|
test "upstream which_function::returns_empty_list_for_missing_executable" {
  let value = try! which_case(
    "missing",
    @host.OperatingSystem::Linux,
    "/workspace",
    None,
    [],
  )
  assert_true(value.elements().is_empty())
}

///|
test "upstream which_function::requires_lists_setting" {
  let cwd = try! @path.PathValue::new("/workspace", @path.Unix)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(@host.OperatingSystem::Linux, "test", @path.Unix),
  )
  let context = EvaluationContext::new(cwd~, lists=false)
  try
    call_non_process_effect_with_context(
      host,
      "which",
      [@value.Value::String("foo")],
      context,
      @source.Span::origin(@source.SourceId::new(929)),
    )
  catch {
    Builtin(@builtin.Failure(message~), ..) =>
      assert_true(message.contains("requires `set lists`"))
    error => fail("unexpected which error: \{Repr(error)}")
  } noraise {
    _ => fail("expected lists setting error")
  }
}

///|
test "upstream which_function::require_success" {
  assert_eq(try! require_case(), @value.Value::String("/workspace/hello.exe"))
}

///|
test "upstream which_function::pathext_ignored_on_non_windows" {
  let value = try! which_case(
    "foo",
    @host.OperatingSystem::Linux,
    "/workspace",
    Some(".EXE"),
    ["foo.exe"],
  )
  assert_true(value.elements().is_empty())
}

///|
test "upstream which_function::pathext_not_applied_when_candidate_has_extension" {
  let value = try! which_case(
    "foo.bat",
    @host.OperatingSystem::Windows,
    "/workspace",
    Some(".EXE"),
    ["foo.bat.exe"],
  )
  assert_true(value.elements().is_empty())
}

///|
test "upstream which_function::handles_absolute_path" {
  let value = try! which_case(
    "/workspace/subdir/foo.exe",
    @host.OperatingSystem::Linux,
    "/workspace/pathdir",
    None,
    ["/workspace/subdir/foo.exe"],
  )
  assert_eq(value.elements(), ["/workspace/subdir/foo.exe"])
}

///|
test "upstream which_function::handles_dir_slash" {
  let value = try! which_case(
    "subdir/foo.exe",
    @host.OperatingSystem::Linux,
    "/workspace/pathdir",
    None,
    ["/workspace/subdir/foo.exe"],
  )
  assert_eq(value.elements(), ["/workspace/subdir/foo.exe"])
}

///|
test "upstream which_function::handles_dotslash" {
  let value = try! which_case(
    "./foo.exe",
    @host.OperatingSystem::Linux,
    "/workspace/pathdir",
    None,
    ["/workspace/foo.exe"],
  )
  assert_eq(value.elements(), ["/workspace/foo.exe"])
}

///|
test "upstream which_function::supports_shadowed_executables" {
  let first = try! which_case(
    "shadowed.exe",
    @host.OperatingSystem::Linux,
    "/workspace/dir1:/workspace/dir2",
    None,
    ["/workspace/dir1/shadowed.exe", "/workspace/dir2/shadowed.exe"],
  )
  let second = try! which_case(
    "shadowed.exe",
    @host.OperatingSystem::Linux,
    "/workspace/dir2:/workspace/dir1",
    None,
    ["/workspace/dir1/shadowed.exe", "/workspace/dir2/shadowed.exe"],
  )
  assert_eq(first.elements(), ["/workspace/dir1/shadowed.exe"])
  assert_eq(second.elements(), ["/workspace/dir2/shadowed.exe"])
}

///|
test "upstream which_function::pathext_custom_extension" {
  let value = try! which_case(
    "foo",
    @host.OperatingSystem::Windows,
    "/workspace",
    Some(".BAR"),
    ["foo.BAR"],
  )
  assert_eq(value.elements(), ["/workspace/foo.BAR"])
}

///|
test "upstream which_function::pathext_entry_missing_dot_is_error" {
  try
    which_case(
      "foo",
      @host.OperatingSystem::Windows,
      "/workspace",
      Some("EXE"),
      ["foo.exe"],
    )
  catch {
    Builtin(@builtin.Failure(message~), ..) =>
      assert_eq(message, "`PATHEXT` entry `EXE` does not start with `.`")
    error => fail("unexpected PATHEXT error: \{Repr(error)}")
  } noraise {
    _ => fail("expected malformed PATHEXT error")
  }
}
