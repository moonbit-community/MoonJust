///|
fn format_datetime(
  millis : Int64,
  offset_seconds : Int32,
  format : String,
  function_name : String,
  span : @source.Span,
) -> String raise EvaluationError {
  @datetime.format(
    millis,
    offset_seconds,
    format,
    utc=function_name == "datetime_utc",
  ) catch {
    error => {
      let detail = match error {
        Invalid =>
          "failed to parse time format string `" +
          format +
          "`: bad or unsupported format string"
        Unformattable =>
          "failed to format time with format string `" + format + "`"
        OutOfRange => "clock value is out of range"
      }
      raise Builtin(
        Failure(
          message="call to function `" + function_name + "` failed: " + detail,
        ),
        span~,
      )
    }
  }
}
