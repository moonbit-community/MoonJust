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
    error => raise Builtin(Failure(message=error.message(format)), span~)
  }
}
