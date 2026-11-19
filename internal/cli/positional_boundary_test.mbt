///|
test "global option aliases and highlight switches are opaque after recipe boundary" {
  let args = [
    "say", "--format", "--highlight", "--no-highlight", "--initialize",
  ]
  for prefix in [[], ["-f", "justfile"], ["--"], ["-f", "justfile", "--"]] {
    let parsed = try! @cli.parse_arguments([..prefix, ..args], Map([]))
    assert_eq(parsed.positional(), args[:])
  }
  let external = try! @cli.parse_arguments(
    ["--command", "echo", "--format", "--set", "x", "y"],
    Map([]),
  )
  assert_eq(external.positional(), ["echo", "--format", "--set", "x", "y"])
}
