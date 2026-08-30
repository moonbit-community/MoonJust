///|
/// Fully composed process output. Streams are bytes to preserve recipe output.
pub struct ApplicationResponse {
  stdout : Bytes
  stderr : Bytes
  exit_code : Int
} derive(Eq, Debug)

///|
pub fn ApplicationResponse::new(
  stdout : Bytes,
  stderr : Bytes,
  exit_code : Int,
) -> ApplicationResponse {
  { stdout, stderr, exit_code, }
}

///|
pub fn ApplicationResponse::success(
  stdout? : Bytes = b"",
  stderr? : Bytes = b"",
) -> ApplicationResponse {
  { stdout, stderr, exit_code: 0, }
}

///|
pub fn ApplicationResponse::stdout(self : ApplicationResponse) -> BytesView {
  self.stdout[:]
}

///|
pub fn ApplicationResponse::stderr(self : ApplicationResponse) -> BytesView {
  self.stderr[:]
}

///|
pub fn ApplicationResponse::exit_code(self : ApplicationResponse) -> Int {
  self.exit_code
}

///|
/// Render a failure into stderr with the separately mapped exit status.
pub fn ApplicationResponse::from_failure(
  failure : ApplicationFailure,
  sources : @source.SourceMap,
) -> ApplicationResponse raise @diagnostic.DiagnosticError {
  let rendered = @diagnostic.render_text(failure.diagnostic(), sources)
  {
    stdout: b"",
    stderr: @utf8.encode(rendered),
    exit_code: failure.exit_code(),
  }
}
