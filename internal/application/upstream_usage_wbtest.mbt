///|
async fn check_usage_cli(
  root : Bytes,
  argv : ArrayView[String],
  stdout~ : Bytes = b"",
  module_source? : Bytes,
  stderr~ : Bytes = b"",
  status~ : Int32 = 0,
) -> Unit {
  let cwd = @path.PathValue::new("/workspace", Unix)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, None, Unix),
  )
  host.put_file(@path.PathValue::new("/workspace/justfile", Unix), root)
  if module_source is Some(bytes) {
    host.put_file(@path.PathValue::new("/workspace/foo.just", Unix), bytes)
  }
  let env = parse_environment(host)
  let arguments = @cli.parse_arguments(argv, env.values())
  let response = run_prepared_cli(host, host, host, arguments, env, b"")
  assert_eq(response.exit_code(), status)
  assert_eq(response.stdout(), stdout)
  assert_eq(response.stderr(), stderr)
}

///|
async test "upstream usage::no_sections" {
  check_usage_cli(b"foo:\n", ["--usage", "foo"], stdout=b"Usage: just foo\n")
}

///|
async test "upstream usage::arguments_only" {
  check_usage_cli(
    b"foo bar:\n",
    ["--usage", "foo"],
    stdout=b"Usage: just foo bar\n\nArguments:\n  bar\n",
  )
}

///|
async test "upstream usage::options_only" {
  check_usage_cli(
    b"[arg('bar', short='b')]\nfoo bar:\n",
    ["--usage", "foo"],
    stdout=b"Usage: just foo [OPTIONS]\n\nOptions:\n  -b bar\n",
  )
}

///|
async test "upstream usage::arguments_and_options" {
  check_usage_cli(
    b"[arg('bar', short='b')]\nfoo bar baz:\n",
    ["--usage", "foo"],
    stdout=b"Usage: just foo [OPTIONS] baz\n\nArguments:\n  baz\n\nOptions:\n  -b bar\n",
  )
}

///|
async test "upstream usage::root_module" {
  check_usage_cli(
    b"# comment\nfoo bar:\n\n[arg('baz', short='b')]\nqux baz:\n",
    ["--usage"],
    stdout=b"Usage:\n    # comment\n    just foo bar\n      bar\n\n    just qux [OPTIONS]\n      -b baz\n",
  )
}

///|
async test "upstream usage::submodule" {
  check_usage_cli(
    b"mod foo\n",
    ["--usage", "foo"],
    stdout=b"Usage:\n    just foo bar\n",
    module_source=b"bar:",
  )
}

///|
async test "upstream usage::module_alias" {
  check_usage_cli(
    b"mod foo\n\nalias f := foo\n",
    ["--usage", "f"],
    stdout=b"Usage:\n    just f bar\n",
    module_source=b"bar:",
  )
}

///|
async test "upstream usage::multi_line_doc" {
  check_usage_cli(
    b"[doc(\"foo\\nbar\")]\nbaz:\n",
    ["--usage"],
    stdout=b"Usage:\n    # foo\n    # bar\n    just baz\n",
  )
}

///|
async test "upstream usage::empty_module" {
  check_usage_cli(
    b"mod foo\n",
    ["--usage", "foo"],
    module_source=b"",
    stderr=b"module contains no recipes\n",
  )
}

///|
async test "upstream usage::empty_module_quiet" {
  check_usage_cli(
    b"mod foo\n",
    ["--quiet", "--usage", "foo"],
    module_source=b"",
  )
}

///|
async test "upstream modules::show_absent_optional_module_is_error" {
  check_usage_cli(
    b"mod? foo\n",
    ["--show", "foo"],
    stderr=b"error: optional module `foo` is absent\n",
    status=1,
  )
}

///|
async test "upstream modules::usage_absent_optional_module_is_error" {
  check_usage_cli(
    b"mod? foo\n",
    ["--usage", "foo"],
    stderr=b"error: optional module `foo` is absent\n",
    status=1,
  )
}

///|
async test "show and usage resolve missing optional ancestors in both path spellings" {
  for command in ["--show", "--usage"] {
    for path in [["foo", "leaf"], ["foo::leaf"]] {
      check_usage_cli(
        b"mod? foo\n",
        [command] + path,
        stderr=b"error: optional module `foo` is absent\n",
        status=1,
      )
    }
  }
}
