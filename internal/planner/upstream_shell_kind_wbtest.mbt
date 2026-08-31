///|
test "upstream shell_kind::tests::from_str" {
  for
    expected in [
      ("foo", true, ""),
      ("cmd", false, ".bat"),
      ("cmd.exe", false, ".bat"),
      ("powershell", false, ".ps1"),
      ("powershell.exe", false, ".ps1"),
      ("pwsh", false, ".ps1"),
      ("pwsh.exe", false, ".ps1"),
    ] {
    let extension = inferred_extension(expected.0)
    assert_eq(extension.is_empty(), expected.1)
    assert_eq(extension, expected.2)
  }
}
