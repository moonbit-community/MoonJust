///|
fn runtime_test_path(
  value : String,
  flavor : @path.PathFlavor,
) -> @path.PathValue {
  try! @path.PathValue::new(value, flavor)
}

///|
test "runtime report helpers preserve bytes and command counts" {
  let report = @executor.ExecutionReport::new(b"out", b"err", 2)
  let prefixed = prepend_report_stderr(b"prefix\n", report)
  assert_eq(prefixed.stdout(), b"out")
  assert_eq(prefixed.stderr(), b"prefix\nerr")
  let suffixed = append_report_stderr(report, b"\nsuffix")
  assert_eq(suffixed.stderr(), b"err\nsuffix")
  let stdout : Array[Byte] = []
  let stderr : Array[Byte] = []
  assert_eq(append_report(stdout, stderr, report), 2)
  assert_eq(stdout, [0x6f, 0x75, 0x74])
  assert_eq(stderr, [0x65, 0x72, 0x72])
  assert_eq(
    running_message("build", false),
    b"===> running recipe `build`...\n",
  )
  assert_eq(
    running_message("build", true),
    b"\x1b[1;36m===> running recipe `build`...\x1b[0m\n",
  )
}

///|
test "runtime errors expose stable messages and output" {
  let command = try! @host.CommandSpec::new("echo", [])
  let failed = @executor.ExecutionError::command_failed("build", 3, 7)
  let runtime = failure_after_report(
    failed,
    @executor.ExecutionReport::new(b"out", b"err", 1),
  )
  assert_eq(runtime.commands(), 1)
  assert_eq(runtime.stdout(), b"out")
  assert_eq(runtime.stderr(), b"err")
  assert_eq(runtime.exit_code(), 7)
  assert_true(runtime.message().contains("build"))
  let live = live_failure(
    @executor.ExecutionError::host(InvalidInput("bad")),
    4,
    show_message=false,
  )
  assert_eq(live.commands(), 4)
  assert_false(live.show_message())
  assert_true(live.message().length() > 0)
  assert_eq(live.exit_code(), 1)
  let live_spec_value = live_spec(command)
  assert_true(live_spec_value.inherits_stdin())
  assert_eq(live_spec_value.stdout(), Inherit)
}

///|
test "runtime host error details and cache paths are classified" {
  let path = runtime_test_path("/tmp/cache", Unix)
  assert_eq(process_error_detail(InvalidInput("bad")), "bad")
  assert_eq(
    process_error_detail(PermissionDenied(Process, detail="denied")),
    "denied",
  )
  assert_eq(
    process_error_detail(NotFound(path)),
    "No such file or directory: /tmp/cache",
  )
  assert_eq(
    process_error_detail(AlreadyExists(path)),
    "already exists: /tmp/cache",
  )
  assert_eq(
    process_error_detail(CapabilityDenied(FsRead)),
    "capability denied: FsRead",
  )
  assert_eq(
    process_error_detail(CapabilityUnavailable(Random)),
    "capability unavailable: Random",
  )
  assert_eq(
    process_error_detail(
      UnexpectedProcess(try! @host.CommandSpec::new("echo", [])),
    ),
    "unexpected process invocation",
  )
  assert_eq(
    process_error_detail(RandomExhausted(requested=2, remaining=0)),
    "host randomness unavailable",
  )
  assert_eq(
    (try! cache_path(path, "artifact")).as_string(),
    "/tmp/cache/artifact",
  )
  try cache_path(path, "bad\u{0000}path") catch {
    Execution(error=CacheFailure(message~), ..) =>
      assert_true(message.contains("invalid cache path"))
    _error => fail("unexpected cache path error")
  } noraise {
    _ => fail("expected invalid cache path")
  }
}

///|
test "runtime helper diagnostics cover exit-message and host classifications" {
  let failed = @executor.ExecutionError::command_failed("build", 2, 7)
  let hidden = live_failure(failed, 3, show_message=false)
  let shown = hidden.with_recipe_exit_message(true)
  assert_true(shown.show_message())
  assert_eq(shown.commands(), 3)
  let host = live_failure(
    @executor.ExecutionError::host(InvalidInput("bad")),
    1,
  )
  assert_true(host.with_recipe_exit_message(false).show_message())
  assert_eq(
    process_error_detail(
      ProcessMismatch(
        expected=try! @host.CommandSpec::new("expected", []),
        actual=try! @host.CommandSpec::new("actual", []),
      ),
    ),
    "unexpected process invocation",
  )
  assert_eq(
    process_error_detail(PermissionDenied(FsWrite, detail="write denied")),
    "write denied",
  )
  assert_eq(
    process_error_detail(CapabilityUnavailable(Clock)),
    "capability unavailable: Clock",
  )
  assert_true(@executor.confirmation_answer_is_yes("Y"))
  assert_true(@executor.confirmation_answer_is_yes(" yes "))
  assert_false(@executor.confirmation_answer_is_yes("no"))
}

///|
priv enum CoverageOutputMode {
  Full
  Short
  Fail
}

///|
priv struct CoverageOutput {
  mode : CoverageOutputMode
}

///|
impl @host.HostAsyncOutput for CoverageOutput with fn write_output(
  self : CoverageOutput,
  _stream : @host.OutputStream,
  bytes : Bytes,
) -> Int raise @host.HostError {
  match self.mode {
    Full => bytes.length()
    Short => Int::max(0, bytes.length() - 1)
    Fail => raise InvalidInput("injected output failure")
  }
}

///|
async test "runtime live output helpers reject short and failed writes" {
  assert_eq(emit_live(CoverageOutput::{ mode: Full }, Stderr, b"ok", 2), 2)
  assert_eq(emit_live(CoverageOutput::{ mode: Full }, Stderr, b"", 2), 0)
  try emit_live(CoverageOutput::{ mode: Short }, Stdout, b"short", 3) catch {
    LiveExecution(error=Host(InvalidInput(message)), commands=3, ..) =>
      assert_true(message.contains("incomplete"))
    error => fail("unexpected short output error: \{Repr(error)}")
  } noraise {
    _ => fail("expected short output error")
  }
  try emit_live(CoverageOutput::{ mode: Fail }, Stdout, b"failed", 4) catch {
    LiveExecution(error=Host(InvalidInput(message)), commands=4, ..) =>
      assert_true(message.contains("failed to write"))
    error => fail("unexpected failed output error: \{Repr(error)}")
  } noraise {
    _ => fail("expected failed output error")
  }
}
