///|
fn path_exists_case(
  argument : String,
  lists : Bool,
  existing : Bool,
) -> String raise EvaluationError {
  let cwd = try! @path.PathValue::new("/workspace", @path.Unix)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(@host.OperatingSystem::Linux, "test", @path.Unix),
  )
  let justfile = try! cwd.join(@path.PathValue::new("justfile", @path.Unix))
  if existing {
    host.put_file(justfile, b"")
  }
  let context = EvaluationContext::new(cwd~, lists~, justfile~)
  let value = call_non_process_effect_with_context(
    host,
    "path_exists",
    [@value.Value::String(argument)],
    context,
    @source.Span::origin(@source.SourceId::new(919)),
  )
  value.display()
}

///|
fn env_function_value(
  key : String,
  platform : @host.OperatingSystem,
) -> String raise EvaluationError {
  let cwd = try! @path.PathValue::new("/workspace", @path.Unix)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(platform, "test", @path.Unix),
  )
  host.set_env(key, "present")
  let context = EvaluationContext::new(cwd~)
  let span = @source.Span::origin(@source.SourceId::new(923))
  let present = call_non_process_effect_with_context(
    host,
    "env_var",
    [@value.Value::String(key)],
    context,
    span,
  )
  let fallback = call_non_process_effect_with_context(
    host,
    "env_var_or_default",
    [@value.Value::String("missing"), @value.Value::String("fallback")],
    context,
    span,
  )
  present.display() + "|" + fallback.display()
}

///|
fn context_effect_value(
  requested : String,
  context : EvaluationContext,
) -> String raise EvaluationError {
  let cwd = try! @path.PathValue::new("/workspace", @path.Unix)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(@host.OperatingSystem::Linux, "test", @path.Unix),
  )
  call_non_process_effect_with_context(
    host,
    requested,
    [],
    context,
    @source.Span::origin(@source.SourceId::new(932)),
  ).to_string()
}

///|
fn context_effect_failure(
  requested : String,
  argument : String,
  context : EvaluationContext,
) -> String {
  let cwd = try! @path.PathValue::new("/workspace", @path.Unix)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(@host.OperatingSystem::Linux, "test", @path.Unix),
  )
  try
    call_non_process_effect_with_context(
      host,
      requested,
      [@value.Value::String(argument)],
      context,
      @source.Span::origin(@source.SourceId::new(933)),
    )
  catch {
    Builtin(@builtin.Failure(message~), ..) => message
    _ => ""
  } noraise {
    _ => ""
  }
}

///|
test "upstream functions::path_exists_empty_path" {
  assert_eq(try! path_exists_case("", false, false), "\"false\"")
}

///|
test "upstream functions::test_path_exists_filepath_doesnt_exist" {
  assert_eq(try! path_exists_case("testfile", false, false), "\"false\"")
}

///|
test "upstream functions::just_pid" {
  let context = EvaluationContext::new(pid=42)
  assert_eq(try! context_effect_value("just_pid", context), "42")
}

///|
test "upstream functions::test_just_executable_function" {
  let executable = try! @path.PathValue::new("/usr/bin/just", @path.Unix)
  let context = EvaluationContext::new(executable~)
  assert_eq(
    try! context_effect_value("just_executable", context),
    "/usr/bin/just",
  )
}

///|
test "upstream functions::source_file" {
  let source_file = try! @path.PathValue::new("/workspace/justfile", @path.Unix)
  assert_eq(
    try! context_effect_value(
      "source_file",
      EvaluationContext::new(source_file~),
    ),
    "/workspace/justfile",
  )
}

///|
test "upstream functions::read_file_not_found" {
  let cwd = try! @path.PathValue::new("/workspace", @path.Unix)
  let message = context_effect_failure(
    "read",
    "bar",
    EvaluationContext::new(cwd~),
  )
  assert_true(
    message.has_prefix(
      "call to function `read` failed: I/O error reading `bar`:",
    ),
  )
}

///|
test "upstream functions::canonicalize" {
  let cwd = try! @path.PathValue::new("/workspace", @path.Unix)
  let source = try! cwd.join(@path.PathValue::new("foo", @path.Unix))
  let canonical = try! @path.PathValue::new("/workspace/justfile", @path.Unix)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(@host.OperatingSystem::Linux, "test", @path.Unix),
  )
  host.set_canonical(source, canonical)
  let context = EvaluationContext::new(cwd~)
  let value = try! call_non_process_effect_with_context(
    host,
    "canonicalize",
    [@value.Value::String("foo")],
    context,
    @source.Span::origin(@source.SourceId::new(934)),
  )
  assert_eq(value.to_string(), "/workspace/justfile")
}

///|
test "upstream directories::cache_directory" {
  let value = try! @path.PathValue::new("/cache", @path.Unix)
  assert_eq(
    try! context_effect_value(
      "cache_directory",
      EvaluationContext::new(cache_directory=value),
    ),
    "/cache",
  )
}

///|
test "upstream directories::config_directory" {
  let value = try! @path.PathValue::new("/config", @path.Unix)
  assert_eq(
    try! context_effect_value(
      "config_directory",
      EvaluationContext::new(config_directory=value),
    ),
    "/config",
  )
}

///|
test "upstream directories::config_local_directory" {
  let value = try! @path.PathValue::new("/config-local", @path.Unix)
  assert_eq(
    try! context_effect_value(
      "config_local_directory",
      EvaluationContext::new(config_local_directory=value),
    ),
    "/config-local",
  )
}

///|
test "upstream directories::data_directory" {
  let value = try! @path.PathValue::new("/data", @path.Unix)
  assert_eq(
    try! context_effect_value(
      "data_directory",
      EvaluationContext::new(data_directory=value),
    ),
    "/data",
  )
}

///|
test "upstream directories::data_local_directory" {
  let value = try! @path.PathValue::new("/data-local", @path.Unix)
  assert_eq(
    try! context_effect_value(
      "data_local_directory",
      EvaluationContext::new(data_local_directory=value),
    ),
    "/data-local",
  )
}

///|
test "upstream directories::home_directory" {
  let value = try! @path.PathValue::new("/home/test", @path.Unix)
  assert_eq(
    try! context_effect_value(
      "home_directory",
      EvaluationContext::new(home_directory=value),
    ),
    "/home/test",
  )
}

///|
test "upstream directories::runtime_directory" {
  let value = try! @path.PathValue::new("/run/user", @path.Unix)
  assert_eq(
    try! context_effect_value(
      "runtime_directory",
      EvaluationContext::new(runtime_directory=value),
    ),
    "/run/user",
  )
}

///|
test "upstream booleans::path_exists_false_is_empty_list" {
  assert_eq(try! path_exists_case("nonexistent", true, false), "[]")
}

///|
test "upstream booleans::path_exists_true_is_true_string" {
  assert_eq(try! path_exists_case("justfile", true, true), "\"true\"")
}

///|
test "upstream booleans::path_exists_without_lists_returns_string" {
  assert_eq(try! path_exists_case("nonexistent", false, false), "\"false\"")
}

///|
test "upstream functions::env_var_functions_unix" {
  assert_eq(
    try! env_function_value("USER", @host.OperatingSystem::Linux),
    "\"present\"|\"fallback\"",
  )
}

///|
test "upstream functions::env_var_functions_windows" {
  assert_eq(
    try! env_function_value("USERNAME", @host.OperatingSystem::Windows),
    "\"present\"|\"fallback\"",
  )
}
