///|
fn fake_context() -> (@host.FakeHost, @application.ApplicationContext) raise {
  let cwd = @path.PathValue::new("/workspace", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  (host, @application.ApplicationContext::new(cwd))
}

///|
test "format check never mutates and reports changed source" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"x:=\"y\"\n")
  let arguments = @cli.parse_arguments(["--fmt", "--check"], {})
  let response = @application.execute_file_command(host, arguments, context)
  assert_eq(response.exit_code(), 1)
  assert_true((try! @utf8.decode(response.stdout())).contains("+x := \"y\""))
  assert_eq(host.read_file(file), b"x:=\"y\"\n")
}

///|
test "format writes only after a successful parse" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"x:=\"y\"\n")
  let arguments = @cli.parse_arguments(["--fmt"], {})
  let response = @application.execute_file_command(host, arguments, context)
  assert_eq(response.exit_code(), 0)
  assert_eq(host.read_file(file), b"x := \"y\"\n")
  host.put_file(file, b"x := \"unterminated\n")
  try @application.execute_file_command(host, arguments, context) catch {
    Load(_) | Format(_) => ()
    error => fail("unexpected application error: \{Repr(error)}")
  } noraise {
    _ => fail("expected malformed source failure")
  }
  assert_eq(host.read_file(file), b"x := \"unterminated\n")
}

///|
test "stdin format returns stdout and does not require a file" {
  let (host, context) = fake_context()
  let context = @application.ApplicationContext::new(
    context.cwd(),
    stdin=b"x:=\"y\"\n",
  )
  let arguments = @cli.parse_arguments(["--fmt", "--justfile", "-"], {})
  let response = @application.execute_file_command(host, arguments, context)
  assert_eq(response.exit_code(), 0)
  assert_eq(response.stdout(), b"x := \"y\"\n")
}

///|
test "init creates the canonical template and refuses overwrite" {
  let (host, context) = fake_context()
  let arguments = @cli.parse_arguments(["--init"], {})
  let response = @application.execute_file_command(host, arguments, context)
  assert_eq(response.exit_code(), 0)
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  assert_true((try! @utf8.decode(host.read_file(file))).contains("default:"))
  try @application.execute_file_command(host, arguments, context) catch {
    AlreadyExists(path) => assert_eq(path, file)
    error => fail("unexpected application error: \{Repr(error)}")
  } noraise {
    _ => fail("expected overwrite refusal")
  }
}

///|
test "format surfaces write denial and accepts upstream dry-run semantics" {
  let (host, context) = fake_context()
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"x:=\"y\"\n")
  let arguments = @cli.parse_arguments(["--fmt", "--dry-run"], {})
  host.deny(FsWrite)
  try @application.execute_file_command(host, arguments, context) catch {
    Host(CapabilityDenied(FsWrite)) => ()
    error => fail("unexpected permission error: \{Repr(error)}")
  } noraise {
    _ => fail("expected write denial")
  }
  assert_eq(host.read_file(file), b"x:=\"y\"\n")
  host.allow(FsWrite)
  ignore(@application.execute_file_command(host, arguments, context))
  assert_eq(host.read_file(file), b"x := \"y\"\n")
}
