///|
test "static changelog response preserves the pinned document bytes" {
  let response = @application.static_invocation_response(["--changelog"]).unwrap()
  assert_eq(response.exit_code(), 0)
  assert_eq(response.stdout().length(), 209131)
  assert_eq(
    @crypto.bytes_to_hex_string(@crypto.sha256(response.stdout())),
    "f904802597ddf0e88788a07882ca69b693e1e941caec508e8817bd5f22ae1f38",
  )
}

///|
test "static manual response preserves the complete roff page" {
  let response = @application.static_invocation_response(["--man"]).unwrap()
  assert_eq(response.exit_code(), 0)
  assert_eq(response.stdout().length(), 8211)
  assert_eq(
    @crypto.bytes_to_hex_string(@crypto.sha256(response.stdout())),
    "7243ceeec8f8dd1a140676d6d1c6855a930bbd0d33e27a81cd1106e28953cc60",
  )
  let text = try! @utf8.decode(response.stdout().to_owned())
  assert_true(text.has_prefix(".ie \\n(.g .ds Aq \\(aq"))
  assert_true(text.has_suffix("Casey Rodarmor <casey@rodarmor.com>\n"))
}
