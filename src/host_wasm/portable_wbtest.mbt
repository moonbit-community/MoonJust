///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
test "portable host normalizes launcher architecture aliases" {
  assert_eq(portable_architecture(Some("arm64")), "aarch64")
  assert_eq(portable_architecture(Some("AMD64")), "x86_64")
  assert_eq(portable_architecture(Some("riscv64")), "riscv64")
  assert_eq(portable_architecture(None), "wasm32")
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
test "portable host reports launcher platform and stable environment" {
  let variables = [
    ("MOONJUST_OS", @env.get_env_var("MOONJUST_OS")),
    ("MOONJUST_ARCH", @env.get_env_var("MOONJUST_ARCH")),
    ("MOONJUST_PID", @env.get_env_var("MOONJUST_PID")),
    ("MOONJUST_NUM_CPUS", @env.get_env_var("MOONJUST_NUM_CPUS")),
    ("MOONJUST_EXECUTABLE", @env.get_env_var("MOONJUST_EXECUTABLE")),
  ]
  defer (for variable in variables {
    let (name, value) = variable
    match value {
      Some(value) => @env.set_env_var(name, value)
      None => @env.unset_env_var(name)
    }
  })
  assert_eq(portable_os(), Other("wasm"))
  assert_eq(portable_flavor(Linux), Unix)
  assert_eq(portable_flavor(Windows), Windows)
  let operating_systems : Array[(String, @host.OperatingSystem)] = [
    ("linux", Linux),
    ("macos", Macos),
    ("darwin", Macos),
    ("windows", Windows),
    ("plan9", Other("plan9")),
  ]
  for entry in operating_systems {
    let (name, expected) = entry
    @env.set_env_var("MOONJUST_OS", name)
    assert_eq(portable_os(), expected)
  }
  @env.set_env_var("MOONJUST_OS", "windows")
  @env.set_env_var("MOONJUST_ARCH", "AMD64")
  @env.set_env_var("MOONJUST_PID", "42")
  @env.set_env_var("MOONJUST_NUM_CPUS", "8")
  @env.set_env_var("MOONJUST_EXECUTABLE", "moonjust.exe")
  let host = PortableHost::new()
  let platform = @host.HostPlatform::platform_info(host)
  assert_eq(platform.operating_system(), Windows)
  assert_eq(platform.architecture(), "x86_64")
  assert_eq(platform.path_flavor(), Windows)
  assert_true(platform.portable_runtime())
  assert_eq(platform.pid(), Some(42))
  assert_eq(platform.num_cpus(), Some(8))
  assert_eq(platform.executable(), Some("moonjust.exe"))
  assert_eq(@host.HostEnv::env_get(host, "MOONJUST_PID"), Some("42"))
  assert_true(@host.HostEnv::env_entries(host).contains(("MOONJUST_PID", "42")))
  assert_eq(portable_positive_int("MOONJUST_PID"), Some(42))
  @env.set_env_var("MOONJUST_PID", "0")
  assert_eq(portable_positive_int("MOONJUST_PID"), None)
  @env.set_env_var("MOONJUST_PID", "invalid")
  assert_eq(portable_positive_int("MOONJUST_PID"), None)
  @env.unset_env_var("MOONJUST_PID")
  assert_eq(portable_positive_int("MOONJUST_PID"), None)
  let terminal = @host.HostTerminal::terminal_info(host)
  assert_false(terminal.stdin_is_terminal())
  assert_false(terminal.stdout_is_terminal())
  assert_false(terminal.stderr_is_terminal())
  assert_false(terminal.color_supported())
  @env.unset_env_var("MOONJUST_EXECUTABLE")
  assert_true(@host.HostPlatform::platform_info(host).executable() is Some(_))
}

///|
#cfg(target="wasm")
async test "portable host exercises bounded filesystem and runtime capabilities" {
  let directory = "_build/portable-host-coverage"
  try @async_fs.rmdir(directory, recursive=true) catch {
    _ => ()
  } noraise {
    _ => ()
  }
  @async_fs.mkdir(directory, recursive=true)
  defer (try @async_fs.rmdir(directory, recursive=true) catch {
    _ => ()
  } noraise {
    _ => ()
  })
  let host = PortableHost::new()
  let root = try! @path.PathValue::new(directory, Unix)
  let path = try! root.join(try! @path.PathValue::new("input", Unix))
  let missing = try! root.join(try! @path.PathValue::new("missing", Unix))
  @host.HostFs::write_file(host, path, b"0123456789")
  assert_eq(@host.HostFs::read_file(host, path), b"0123456789")
  assert_eq(@host.HostFs::read_file_range(host, path, 2L, 4), b"2345")
  assert_eq(@host.HostFs::read_file_range(host, path, 10L, 4), b"")
  for range in [(-1L, 1), (0L, -1), (0x8000_0000L, 1)] {
    let (offset, length) = range
    try
      ignore(@host.HostFs::read_file_range(host, path, offset, length))
    catch {
      InvalidInput(_) => ()
      error => fail("unexpected portable range error: \{Repr(error)}")
    } noraise {
      _ => fail("expected invalid portable range")
    }
  }
  assert_true(@host.HostFs::file_exists(host, path))
  assert_false(@host.HostFs::file_exists(host, missing))
  assert_true(@host.HostFs::read_dir(host, root).contains("input"))
  assert_eq(@host.HostFs::metadata(host, path).size(), 10L)
  assert_true(@host.HostFs::metadata(host, root).is_directory())
  assert_eq(@host.HostFs::canonicalize(host, path), path)
  assert_eq(@host.HostSourceReader::read_source(host, path, 4), b"01234")
  assert_eq(@host.HostSourceReader::read_source(host, path, 20), b"0123456789")
  for limit in [-1, 0x7fff_ffff] {
    try ignore(@host.HostSourceReader::read_source(host, path, limit)) catch {
      InvalidInput(_) => ()
      error => fail("unexpected source limit error: \{Repr(error)}")
    } noraise {
      _ => fail("expected invalid source limit")
    }
  }
  try ignore(@host.HostFs::read_file(host, missing)) catch {
    InvalidInput(_) => ()
    error => fail("unexpected missing file error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing file failure")
  }
  try ignore(@host.HostFs::read_file_range(host, missing, 0L, 4)) catch {
    InvalidInput(_) => ()
    error => fail("unexpected missing range error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing range failure")
  }
  try ignore(@host.HostFs::read_dir(host, missing)) catch {
    NotFound(path) => assert_eq(path, missing)
    error => fail("unexpected missing directory error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing directory failure")
  }
  try ignore(@host.HostFs::metadata(host, missing)) catch {
    InvalidInput(_) => ()
    error => fail("unexpected missing metadata error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing metadata failure")
  }
  try ignore(@host.HostSourceReader::read_source(host, missing, 4)) catch {
    InvalidInput(_) => ()
    error => fail("unexpected missing source error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing source failure")
  }
  try @host.HostFs::write_file(host, root, b"denied") catch {
    InvalidInput(_) => ()
    error => fail("unexpected directory write error: \{Repr(error)}")
  } noraise {
    _ => fail("expected directory write failure")
  }
  try @host.HostFs::persist_temp_file(host, path, missing, false) catch {
    CapabilityUnavailable(FsWrite) => ()
    error => fail("unexpected portable persistence error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unavailable portable persistence")
  }
  assert_true(@host.HostClock::now_millis(host) >= 0L)
  assert_eq(@host.HostRandom::random_bytes(host, 4).length(), 4)
  try ignore(@host.HostRandom::random_bytes(host, -1)) catch {
    InvalidInput(_) => ()
    error => fail("unexpected random count error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid random count")
  }
}
