///|
fn failure(message : String, exit_code : Int) -> @cli.ApplicationResponse {
  @cli.ApplicationResponse::new(
    b"",
    @utf8.encode(message.trim_end().to_owned() + "\n"),
    exit_code,
  )
}

///|
const MOONJUST_CHANGELOG : String =
  #|Changelog
  #|=========
  #|
  #|MoonJust is a pure MoonBit executable compatible with just 1.57.0.
  #|The repository contains the executable, internal implementation packages,
  #|and functional compatibility runners.

///|
pub fn static_invocation_text(argv : ArrayView[String]) -> String? {
  if argv.length() != 1 {
    return None
  }
  match argv[0] {
    "--help" | "-h" => Some(@cli.render_help().trim_end().to_owned())
    "--version" | "-V" => Some(version_line())
    "--changelog" => Some(MOONJUST_CHANGELOG)
    "--man" => Some(JUST_MAN_PAGE)
    _ => None
  }
}

///|
pub fn static_invocation_response(
  argv : ArrayView[String],
) -> @cli.ApplicationResponse? {
  static_invocation_text(argv).map(text => {
    @cli.ApplicationResponse::success(stdout=@utf8.encode(text + "\n"))
  })
}
