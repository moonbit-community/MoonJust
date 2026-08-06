///|
fn fake() -> @host.FakeHost raise @path.PathError {
  let cwd = @path.PathValue::new("/workspace", Unix)
  let platform = @host.PlatformInfo::new(Linux, "x86_64", Unix)
  @host.FakeHost::new(cwd, platform)
}

///|
test "memory filesystem is isolated and capability checked" {
  let host = fake()
  let path = @path.PathValue::new("/workspace/justfile", Unix)
  assert_false(host.file_exists(path))
  host.write_file(path, b"build:\n")
  assert_true(host.file_exists(path))
  assert_eq(host.read_file(path), b"build:\n")
  let missing = @path.PathValue::new("/workspace/missing", Unix)
  try host.read_file(missing) catch {
    NotFound(actual) => assert_eq(actual, missing)
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing file")
  }
  host.deny(FsRead)
  try host.read_file(path) catch {
    CapabilityDenied(FsRead) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected denied read")
  }
  host.allow(FsRead)
  assert_eq(host.read_file(path), b"build:\n")
}

///|
test "file ranges and stream helper keep chunk sizes bounded" {
  let host = fake()
  let path = @path.PathValue::new("/workspace/data", Unix)
  host.put_file(path, b"0123456789abcdef")
  assert_eq(host.read_file_range(path, 3L, 5), b"34567")
  assert_eq(host.read_file_range(path, 14L, 8), b"ef")
  let collected : Array[Byte] = []
  let max_chunk = Ref(0)
  @host.stream_file(host, path, chunk_size=3, fn(bytes) {
    max_chunk.val = Int::max(max_chunk.val, bytes.length())
    for byte in bytes {
      collected.push(byte)
    }
  })
  assert_eq(Bytes::from_array(collected), b"0123456789abcdef")
  assert_eq(max_chunk.val, 3)
}

///|
test "environment and working directory are deterministic" {
  let host = fake()
  host.set_env("MODE", "test")
  assert_eq(host.env_get("MODE"), Some("test"))
  assert_eq(host.env_get("MISSING"), None)
  assert_eq(host.current_dir().as_string(), "/workspace")
  host.deny(Environment)
  try host.env_get("MODE") catch {
    CapabilityDenied(Environment) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected denied environment")
  }
}

///|
test "clock and random stream have no ambient inputs" {
  let host = fake()
  host.set_clock_millis(1722780000123L)
  host.set_random_stream(b"abcdef")
  assert_eq(host.now_millis(), 1722780000123L)
  assert_eq(host.random_bytes(2), b"ab")
  assert_eq(host.random_bytes(3), b"cde")
  try host.random_bytes(2) catch {
    RandomExhausted(requested=2, remaining=1) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected exhausted random stream")
  }
}

///|
test "process requests match structured expectations exactly" {
  let host = fake()
  let command = @host.CommandSpec::new("sh", ["-c", "printf ok"])
  command.set_cwd(@path.PathValue::new("/workspace", Unix))
  command.add_environment("MODE", "test")
  command.set_stdin(b"input")
  let output = @host.ProcessOutput::new(7, b"ok", b"warning")
  host.expect_process(command, output)
  assert_eq(host.run_process(command), output)
  assert_eq(host.process_calls().length(), 1)
  assert_eq(host.pending_process_expectations(), 0)
  try host.run_process(command) catch {
    UnexpectedProcess(actual) => assert_eq(actual, command)
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected an unexpected process error")
  }
}

///|
test "process mismatches report expected and actual requests" {
  let host = fake()
  let expected = @host.CommandSpec::new("just", ["build"])
  let actual = @host.CommandSpec::new("just", ["test"])
  host.expect_process(expected, @host.ProcessOutput::new(0, b"", b""))
  try host.run_process(actual) catch {
    ProcessMismatch(expected=seen_expected, actual=seen_actual) => {
      assert_eq(seen_expected, expected)
      assert_eq(seen_actual, actual)
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected process mismatch")
  }
}

///|
test "terminal, signal, and platform observations are queued values" {
  let host = fake()
  let terminal = @host.TerminalInfo::new(false, true, true, true)
  host.set_terminal(terminal)
  host.push_signal(Interrupt)
  host.push_signal(OtherSignal(9))
  assert_eq(host.terminal_info(), terminal)
  assert_eq(host.pending_signal(), Some(Interrupt))
  assert_eq(host.pending_signal(), Some(OtherSignal(9)))
  assert_eq(host.pending_signal(), None)
  let platform = host.platform_info()
  assert_eq(platform.operating_system(), Linux)
  assert_eq(platform.architecture(), "x86_64")
  assert_eq(platform.path_flavor(), Unix)
  host.deny(Platform)
  try host.platform_info() catch {
    CapabilityDenied(Platform) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected denied platform")
  }
}

///|
test "unavailable capabilities remain distinct from policy denial" {
  let host = fake()
  host.mark_unavailable(Process)
  let command = @host.CommandSpec::new("just", ["build"])
  try host.run_process(command) catch {
    CapabilityUnavailable(Process) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unavailable process capability")
  }
  host.mark_available(Process)
  host.deny(Process)
  try host.run_process(command) catch {
    CapabilityDenied(Process) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected denied process capability")
  }
}

///|
test "command validation rejects ambiguous process input" {
  try @host.CommandSpec::new("", []) catch {
    InvalidInput("process program must not be empty") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected empty program rejection")
  }
  let command = @host.CommandSpec::new("env", [])
  try command.add_environment("BAD=KEY", "value") catch {
    InvalidInput("invalid process environment entry") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected environment validation error")
  }
}
