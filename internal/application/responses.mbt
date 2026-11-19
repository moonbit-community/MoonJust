///|
fn failure(message : String, exit_code : Int32) -> @cli.ApplicationResponse {
  @cli.ApplicationResponse::new(
    b"",
    @utf8.encode(message.trim_end().to_owned() + "\n"),
    exit_code,
  )
}

///|
pub fn static_invocation_text(argv : ArrayView[String]) -> String? {
  if argv.length() != 1 {
    return None
  }
  match argv[0] {
    "--help" | "-h" => Some(@cli.render_help().trim_end().to_owned() + "\n")
    "--version" | "-V" => Some(version_line() + "\n")
    "--changelog" => Some(just_changelog)
    "--man" => Some(JUST_MAN_PAGE + "\n")
    _ => None
  }
}

///|
pub fn static_invocation_response(
  argv : ArrayView[String],
) -> @cli.ApplicationResponse? {
  static_invocation_text(argv).map(text => {
    @cli.ApplicationResponse::success(stdout=@utf8.encode(text))
  })
}
