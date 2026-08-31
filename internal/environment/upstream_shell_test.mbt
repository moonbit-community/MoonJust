///|
fn shell_platform(windows : Bool) -> PlatformConfiguration {
  let info = if windows {
    @host.PlatformInfo::new(@host.Windows, "unknown", @path.Windows)
  } else {
    @host.PlatformInfo::new(@host.Linux, "unknown", @path.Unix)
  }
  PlatformConfiguration::new(info)
}

///|
fn shell_config(
  program : String,
  arguments : Array[String],
) -> ShellConfiguration {
  try! ShellConfiguration::new(program, arguments)
}

///|
test "upstream settings::tests::default_shell" {
  let shell = try! resolve_shell(shell_platform(false))
  assert_eq(shell.program(), "sh")
  assert_eq(shell.arguments(), ["-cu"])
}

///|
test "upstream settings::tests::default_shell_powershell" {
  let unix = try! resolve_shell(shell_platform(false), windows_powershell=true)
  assert_eq(unix.program(), "sh")
  assert_eq(unix.arguments(), ["-cu"])
  let windows = try! resolve_shell(
    shell_platform(true),
    windows_powershell=true,
  )
  assert_eq(windows.program(), "powershell.exe")
  assert_eq(windows.arguments(), ["-NoLogo", "-Command"])
}

///|
test "upstream settings::tests::overwrite_shell" {
  let shell = try! resolve_shell(
    shell_platform(false),
    setting_shell=Some(shell_config("lol", ["-nice"])),
  )
  assert_eq(shell.program(), "lol")
  assert_eq(shell.arguments(), ["-nice"])
}

///|
test "upstream settings::tests::overwrite_shell_powershell" {
  let shell = try! resolve_shell(
    shell_platform(true),
    cli_shell=Some("lol"),
    cli_arguments=Some(["-nice"]),
    windows_powershell=true,
  )
  assert_eq(shell.program(), "lol")
  assert_eq(shell.arguments(), ["-nice"])
}

///|
test "upstream settings::tests::shell_args_present_but_not_shell" {
  let shell = try! resolve_shell(
    shell_platform(true),
    cli_arguments=Some(["-nice"]),
    windows_powershell=true,
  )
  assert_eq(shell.program(), "sh")
  assert_eq(shell.arguments(), ["-nice"])
}

///|
test "upstream settings::tests::shell_cooked" {
  let shell = try! resolve_shell(
    shell_platform(false),
    setting_shell=Some(shell_config("asdf.exe", ["-nope"])),
  )
  assert_eq(shell.program(), "asdf.exe")
  assert_eq(shell.arguments(), ["-nope"])
}

///|
test "upstream settings::tests::shell_present_but_not_shell_args" {
  let shell = try! resolve_shell(
    shell_platform(true),
    cli_shell=Some("lol"),
    windows_powershell=true,
  )
  assert_eq(shell.program(), "lol")
}

///|
test "upstream shell::cmd" {
  let shell = shell_config("cmd.exe", ["/C"])
  assert_eq(shell.program(), "cmd.exe")
  assert_eq(shell.arguments(), ["/C"])
}

///|
test "upstream shell::powershell" {
  let shell = shell_config("powershell.exe", ["-c"])
  assert_eq(shell.program(), "powershell.exe")
  assert_eq(shell.arguments(), ["-c"])
}

///|
test "upstream shell::flag" {
  let shell = shell_config("/tmp/shell", ["-cu"])
  assert_eq(shell.program(), "/tmp/shell")
  assert_eq(shell.arguments(), ["-cu"])
}
