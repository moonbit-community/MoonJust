///|
test "contract JUST-1.57.0-0417 config::tests::set_bad" {
  try parse_arguments(["--set", "0::invalid", "value"], {}) catch {
    Config(message) =>
      assert_eq(message, "error: invalid override path `0::invalid`")
    _ => fail("unexpected configuration error")
  } noraise {
    _ => fail("expected invalid override path")
  }
}
