///|
fn zero_pad(value : Int, width : Int) -> String {
  value.to_string().pad_start(width, '0')
}

///|
fn weekday_names(day : @time.Weekday) -> (String, String) {
  match day {
    Monday => ("Mon", "Monday")
    Tuesday => ("Tue", "Tuesday")
    Wednesday => ("Wed", "Wednesday")
    Thursday => ("Thu", "Thursday")
    Friday => ("Fri", "Friday")
    Saturday => ("Sat", "Saturday")
    Sunday => ("Sun", "Sunday")
  }
}

///|
fn month_names(month : Int) -> (String, String) {
  let short = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
    "Dec",
  ]
  let long = [
    "January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December",
  ]
  (short[month - 1], long[month - 1])
}

///|
fn offset_text(seconds : Int, colon : Bool) -> String {
  let sign = if seconds < 0 { "-" } else { "+" }
  let absolute = seconds.abs()
  let hours = absolute / 3600
  let minutes = absolute % 3600 / 60
  sign +
  zero_pad(hours, 2) +
  (if colon { ":" } else { "" }) +
  zero_pad(minutes, 2)
}

///|
fn format_datetime(
  millis : Int64,
  offset_seconds : Int,
  format : String,
  function_name : String,
  span : @source.Span,
) -> String raise EvaluationError {
  let mut unix_seconds = millis / 1000L
  let mut remainder = (millis % 1000L).to_int()
  if remainder < 0 {
    unix_seconds -= 1L
    remainder += 1000
  }
  let offset = @time.ZoneOffset::from_seconds(offset_seconds) catch {
    _ => raise Builtin(Failure(message="invalid UTC offset"), span~)
  }
  let datetime = @time.PlainDateTime::from_unix_second(
    unix_seconds,
    remainder * 1_000_000,
    offset,
  ) catch {
    _ => raise Builtin(Failure(message="clock value is out of range"), span~)
  }
  let characters = format.to_array()
  let builder = StringBuilder()
  let mut index = 0
  while index < characters.length() {
    if characters[index] != '%' {
      builder.write_char(characters[index])
      index += 1
      continue
    }
    if index + 1 >= characters.length() {
      raise Builtin(Failure(message="datetime format ends with `%`"), span~)
    }
    let directive = characters[index + 1]
    if directive == ':' &&
      index + 2 < characters.length() &&
      characters[index + 2] == 'z' {
      builder.write_string(offset_text(offset_seconds, true))
      index += 3
      continue
    }
    let (weekday_short, weekday_long) = weekday_names(datetime.weekday())
    let (month_short, month_long) = month_names(datetime.month())
    let text = match directive {
      '%' => "%"
      'Y' => zero_pad(datetime.year(), 4)
      'y' => zero_pad(datetime.year() % 100, 2)
      'm' => zero_pad(datetime.month(), 2)
      'b' | 'h' => month_short
      'B' => month_long
      'd' => zero_pad(datetime.day(), 2)
      'e' => datetime.day().to_string().pad_start(2, ' ')
      'H' => zero_pad(datetime.hour(), 2)
      'I' => {
        let hour = datetime.hour() % 12
        zero_pad(if hour == 0 { 12 } else { hour }, 2)
      }
      'M' => zero_pad(datetime.minute(), 2)
      'S' => zero_pad(datetime.second(), 2)
      'f' => zero_pad(datetime.nanosecond(), 9)
      'a' => weekday_short
      'A' => weekday_long
      'j' => zero_pad(datetime.ordinal(), 3)
      'p' => if datetime.hour() < 12 { "AM" } else { "PM" }
      'z' => offset_text(offset_seconds, false)
      'Z' =>
        if offset_seconds == 0 {
          "UTC"
        } else {
          offset_text(offset_seconds, false)
        }
      's' => unix_seconds.to_string()
      '#' =>
        raise Builtin(
          Failure(
            message="call to function `" +
              function_name +
              "` failed: failed to format time with format string `" +
              format +
              "`",
          ),
          span~,
        )
      _ =>
        raise Builtin(
          Failure(
            message="call to function `" +
              function_name +
              "` failed: failed to parse time format string `" +
              format +
              "`: bad or unsupported format string",
          ),
          span~,
        )
    }
    builder.write_string(text)
    index += 2
  }
  builder.to_string()
}
