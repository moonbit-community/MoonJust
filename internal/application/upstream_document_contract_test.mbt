///|
test "static changelog response preserves the pinned document bytes" {
  let response = @application.static_invocation_response(["--changelog"]).unwrap()
  assert_eq(response.exit_code(), 0)
  assert_eq(response.stdout().length(), 213523)
  assert_eq(
    @crypto.bytes_to_hex_string(@crypto.sha256(response.stdout())),
    "0dce88c74adb5a3d4b3418a66bd3a75be54fd85f9eee7de44de5f593b87462a2",
  )
}

///|
test "static manual response preserves the complete roff page" {
  let response = @application.static_invocation_response(["--man"]).unwrap()
  assert_eq(response.exit_code(), 0)
  assert_eq(response.stdout().length(), 8313)
  assert_eq(
    @crypto.bytes_to_hex_string(@crypto.sha256(response.stdout())),
    "96a00b5434c031884dc0b1ff24ed6a6ed19745e54beb419d84bf407c01f6b701",
  )
  let text = try! @utf8.decode(response.stdout().to_owned())
  assert_true(text.has_prefix(".ie \\n(.g .ds Aq \\(aq"))
  assert_true(text.has_suffix("Casey Rodarmor <casey@rodarmor.com>\n"))
}
