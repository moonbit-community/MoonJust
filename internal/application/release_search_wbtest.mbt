///|
fn release_search_input(
  flavor : @path.PathFlavor,
) -> (@project.ProjectInput, @host_testkit.FakeHost) raise @path.PathError {
  let cwd = @path.PathValue::new(
    if flavor == Windows {
      "C:/workspace"
    } else {
      "/workspace"
    },
    flavor,
  )
  let platform = @host.PlatformInfo::new(
    if flavor == Windows {
      Windows
    } else {
      Linux
    },
    None,
    flavor,
  )
  (@project.ProjectInput::new(cwd), @host_testkit.FakeHost::new(cwd, platform))
}

///|
fn search_child(
  path : @path.PathValue,
  name : String,
) -> @path.PathValue raise @path.PathError {
  path.join(@path.PathValue::new(name, path.flavor()))
}

///|
test "upstream config::tests::search_config_from_working_directory" {
  for
    (argv, env) in [
      (["--working-directory", "sub"], Map([])),
      (["-dsub"], { "JUST_WORKING_DIRECTORY": "unused" }),
      ([], { "JUST_WORKING_DIRECTORY": "sub" }),
    ] {
    let arguments = try! @cli.parse_arguments(argv, env)
    assert_eq(try! input_selection(arguments, Unix), Search)
    assert_eq(
      try! working_directory_argument(arguments, Unix),
      Some(@path.PathValue::new("sub", Unix)),
    )
  }
}

///|
async test "upstream init::working_directory_without_justfile" {
  for flavor in [@path.PathFlavor::Unix, Windows] {
    let (input, host) = release_search_input(flavor)
    let root = input.cwd()
    host.put_directory(search_child(root, ".git"))
    let sub = search_child(root, "sub")
    host.put_directory(sub)
    let arguments = try! @cli.parse_arguments(
      ["--initialize", "-d", "sub"],
      Map([]),
    )
    let response = try! execute_file_command(host, host, arguments, input)
    assert_eq(response.exit_code(), 0)
    assert_eq(
      try! host.read_file(search_child(sub, "justfile")),
      @utf8.encode(INIT_TEMPLATE),
    )
    assert_false(try! host.file_exists(search_child(root, "justfile")))

    let named = try! @cli.parse_arguments(
      [
        "--init", "--justfile-name", "First,Second", "--justfile-name", "Last", "sub/",
      ],
      Map([]),
    )
    ignore(try! execute_file_command(host, host, named, input))
    assert_eq(
      try! host.read_file(search_child(root, "First")),
      @utf8.encode(INIT_TEMPLATE),
    )
  }
}

///|
async fn check_named_discovery(argv : Array[String]) -> Unit {
  for flavor in [@path.PathFlavor::Unix, Windows] {
    let (input, host) = release_search_input(flavor)
    let root = input.cwd()
    let custom = search_child(root, "BAR")
    host.put_file(custom, b"found:\n")
    host.put_file(search_child(root, "justfile"), b"ignored:\n")
    let arguments = try! @cli.parse_arguments(argv, {
      "JUST_JUSTFILE_NAME": "justfile",
    })
    let (loaded, _) = try! load_input_with_directories(host, arguments, input)
    assert_eq(loaded.path(), custom)
  }
}

///|
async test "upstream search::justfile_name_may_be_repeated" {
  check_named_discovery(["--justfile-name", "foo", "--justfile-name", "bar"])
}

///|
async test "upstream search::justfile_name_accepts_comma_separated_values" {
  check_named_discovery(["--justfile-name=foo,bar"])
}

///|
async test "named discovery distinguishes omitted and empty lists and reports all matching entries" {
  for flavor in [@path.PathFlavor::Unix, Windows] {
    let (input, host) = release_search_input(flavor)
    let root = input.cwd()
    let hidden = search_child(root, ".justfile")
    host.put_file(hidden, b"hidden:\n")
    let omitted = try! @cli.parse_arguments([], Map([]))
    assert_eq(
      (try! load_input_with_directories(host, omitted, input)).0.path(),
      hidden,
    )
    for
      (argv, env) in [
        (["--justfile-name="], Map([])),
        (["--justfile-name=,"], Map([])),
        (["--justfile-name", "justfile"], Map([])),
        ([], { "JUST_JUSTFILE_NAME": "" }),
      ] {
      let args = try! @cli.parse_arguments(argv, env)
      try load_input_with_directories(host, args, input) catch {
        Load(NoJustfileFound(_)) => ()
        error => fail("unexpected discovery error: \{Repr(error)}")
      } noraise {
        _ => fail("unexpected match")
      }
    }
    host.put_file(search_child(root, "a"), b"a:\n")
    host.put_file(search_child(root, "B"), b"b:\n")
    let names = try! @cli.parse_arguments([], { "JUST_JUSTFILE_NAME": "b,A,B" })
    try load_input_with_directories(host, names, input) catch {
      Load(AmbiguousJustfile(directory~, found~)) => {
        assert_eq(directory, root)
        assert_eq(found, ["B", "a"])
      }
      error => fail("unexpected discovery error: \{Repr(error)}")
    } noraise {
      _ => fail("expected ambiguity")
    }
  }
}

///|
async test "upstream working_directory::working_directory_without_justfile" {
  for flavor in [@path.PathFlavor::Unix, Windows] {
    let (input, host) = release_search_input(flavor)
    let root = input.cwd()
    let sub = search_child(root, "sub")
    host.put_directory(sub)
    let parent_file = search_child(root, "justfile")
    host.put_file(parent_file, b"foo:\n")
    let args = try! @cli.parse_arguments(["-d", "sub", "foo"], Map([]))
    let request = try! project_load_request(
      args,
      input,
      @semantic.TargetPlatform::new(Linux, true),
      [],
    )
    let directories = (try! @project.load_sources(host, request)).directories()
    assert_eq(directories.justfile(), Some(parent_file))
    assert_eq(directories.project_directory(), sub)
    assert_eq(directories.invocation_directory(), root)
  }
}

///|
async test "upstream working_directory::working_directory_without_justfile_searches_from_working_directory" {
  for flavor in [@path.PathFlavor::Unix, Windows] {
    let (input, host) = release_search_input(flavor)
    let root = input.cwd()
    let file = search_child(root, "sub/justfile")
    host.put_file(file, b"foo:\n")
    host.put_file(search_child(root, "justfile"), b"wrong:\n")
    let args = try! @cli.parse_arguments(
      ["--working-directory=sub", "foo"],
      Map([]),
    )
    let request = try! project_load_request(
      args,
      input,
      @semantic.TargetPlatform::new(Linux, true),
      [],
    )
    let sources = try! @project.load_sources(host, request)
    assert_eq(sources.graph().files()[0].path(), file)
    assert_eq(sources.directories().project_directory(), file.parent().unwrap())
  }
}

///|
async test "an absolute ceiling includes its directory and a relative ceiling does not match absolute ancestors" {
  for flavor in [@path.PathFlavor::Unix, Windows] {
    let (input, host) = release_search_input(flavor)
    let root = input.cwd()
    let sub = search_child(root, "sub")
    host.put_directory(sub)
    let file = search_child(root, "justfile")
    host.put_file(file, b"found:\n")
    for ceiling in ["sub", root.as_string()] {
      let args = try! @cli.parse_arguments(
        ["-d", "sub", "--ceiling", ceiling],
        Map([]),
      )
      assert_eq(
        (try! load_input_with_directories(host, args, input)).0.path(),
        file,
      )
    }
    let args = try! @cli.parse_arguments(
      ["-d", "sub", "--ceiling", sub.as_string()],
      Map([]),
    )
    try load_input_with_directories(host, args, input) catch {
      Load(NoJustfileFound(_)) => ()
      error => fail("unexpected discovery error: \{Repr(error)}")
    } noraise {
      _ => fail("search escaped its ceiling")
    }
  }
}
