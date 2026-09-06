///|
fn assert_upstream_shebang(
  text : String,
  expected : (String, String?)?,
) -> Unit raise {
  let actual = parse_shebang(text).map(value => {
    (value.interpreter, value.argument)
  })
  assert_eq(actual, expected)
}

///|
test "upstream shebang::tests::split_shebang" {
  assert_upstream_shebang("#!    ", None)
  assert_upstream_shebang("#!", None)
  assert_upstream_shebang("#!/bin/bash", Some(("/bin/bash", None)))
  assert_upstream_shebang("#!/bin/bash    ", Some(("/bin/bash", None)))
  assert_upstream_shebang(
    "#!/usr/bin/env python",
    Some(("/usr/bin/env", Some("python"))),
  )
  assert_upstream_shebang(
    "#!/usr/bin/env python   ",
    Some(("/usr/bin/env", Some("python"))),
  )
  assert_upstream_shebang(
    "#!/usr/bin/env python -x",
    Some(("/usr/bin/env", Some("python -x"))),
  )
  assert_upstream_shebang(
    "#!/usr/bin/env python   -x",
    Some(("/usr/bin/env", Some("python   -x"))),
  )
  assert_upstream_shebang(
    "#!/usr/bin/env python \t-x\t",
    Some(("/usr/bin/env", Some("python \t-x"))),
  )
  assert_upstream_shebang("#/usr/bin/env python \t-x\t", None)
  assert_upstream_shebang("#!  /bin/bash", Some(("/bin/bash", None)))
  assert_upstream_shebang("#!\t\t/bin/bash    ", Some(("/bin/bash", None)))
  assert_upstream_shebang(
    "#!  \t\t/usr/bin/env python",
    Some(("/usr/bin/env", Some("python"))),
  )
  assert_upstream_shebang(
    "#!  /usr/bin/env python   ",
    Some(("/usr/bin/env", Some("python"))),
  )
  assert_upstream_shebang(
    "#!  /usr/bin/env python -x",
    Some(("/usr/bin/env", Some("python -x"))),
  )
  assert_upstream_shebang(
    "#!  /usr/bin/env python   -x",
    Some(("/usr/bin/env", Some("python   -x"))),
  )
  assert_upstream_shebang(
    "#!  /usr/bin/env python \t-x\t",
    Some(("/usr/bin/env", Some("python \t-x"))),
  )
  assert_upstream_shebang("#  /usr/bin/env python \t-x\t", None)
}

///|
test "upstream shebang::tests::interpreter_filename_with_forward_slash" {
  assert_eq(
    executable_name(parse_shebang("#!/foo/bar/baz").unwrap().interpreter),
    "baz",
  )
}

///|
test "upstream shebang::tests::interpreter_filename_with_backslash" {
  assert_eq(
    executable_name(parse_shebang("#!\\foo\\bar\\baz").unwrap().interpreter),
    "baz",
  )
}

///|
test "upstream shebang::tests::dont_include_shebang_line_cmd" {
  let platform = @host.PlatformInfo::new(Linux, "test", Unix)
  assert_false(include_shebang_line("cmd", platform))
}

///|
test "upstream shebang::tests::dont_include_shebang_line_cmd_exe" {
  let platform = @host.PlatformInfo::new(Linux, "test", Unix)
  assert_false(include_shebang_line("cmd.exe", platform))
}

///|
test "upstream shebang::tests::include_shebang_line_other" {
  let unix = @host.PlatformInfo::new(Linux, "test", Unix)
  let windows = @host.PlatformInfo::new(Windows, "test", Windows)
  assert_true(include_shebang_line("foo", unix))
  assert_false(include_shebang_line("foo", windows))
}

///|
test "upstream executor::tests::needs_bom" {
  for
    expected in [
      ("powershell", true),
      ("powershell.exe", true),
      ("pwsh", true),
      ("pwsh.exe", true),
      ("cmd", false),
      ("cmd.exe", false),
      ("bash", false),
      ("/bin/sh", false),
      ("python", false),
    ] {
    assert_eq(needs_bom(expected.0), expected.1)
  }
}

///|
test "upstream executor::tests::shebang_script_filename" {
  for
    expected in [
      ("bar", "foo", Some(".sh"), "foo.sh"),
      ("pwsh.exe", "foo", Some(".sh"), "foo.sh"),
      ("cmd.exe", "foo", Some(".sh"), "foo.sh"),
      ("powershell", "foo", None, "foo.ps1"),
      ("pwsh", "foo", None, "foo.ps1"),
      ("powershell.exe", "foo", None, "foo.ps1"),
      ("pwsh.exe", "foo", None, "foo.ps1"),
      ("cmd", "foo", None, "foo.bat"),
      ("cmd.exe", "foo", None, "foo.bat"),
      ("bar", "foo", None, "foo"),
    ] {
    assert_eq(
      expected.1 + expected.2.unwrap_or(inferred_extension(expected.0)),
      expected.3,
    )
  }
}

///|
test "upstream misc::windows_interpreter_path_no_base" {
  assert_eq(executable_name("powershell"), "powershell")
  assert_eq(inferred_extension("powershell"), ".ps1")
  assert_false(
    include_shebang_line(
      "powershell",
      @host.PlatformInfo::new(Windows, "test", Windows),
    ),
  )
}
