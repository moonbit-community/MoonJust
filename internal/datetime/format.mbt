///|
fn zero_pad(value : Int32, width : Int32) -> String {
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
fn month_names(month : Int32) -> (String, String) {
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
fn offset_text(seconds : Int32, colon : Bool) -> String {
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
pub(all) suberror FormatError {
  Invalid
  Unformattable
  OutOfRange
}

///|
pub fn FormatError::message(self : FormatError, format : String) -> String {
  match self {
    Invalid =>
      "failed to parse time format string `\{format}`: bad or unsupported format string"
    Unformattable => "failed to format time with format string `\{format}`"
    OutOfRange => "clock value is out of range"
  }
}

///|
pub fn format(
  millis : Int64,
  offset_seconds : Int32,
  pattern : String,
  utc~ : Bool = false,
) -> String raise FormatError {
  let rem = ((millis % 1000L).to_int() + 1000) % 1000
  let seconds = millis / 1000L - (if millis % 1000L < 0L { 1L } else { 0L })
  let offset = @time.ZoneOffset::from_seconds(offset_seconds) catch {
    _ => raise OutOfRange
  }
  let dt = @time.PlainDateTime::from_unix_second(
    seconds,
    rem * 1_000_000,
    offset,
  ) catch {
    _ => raise OutOfRange
  }
  let (day_short, day_long) = weekday_names(dt.weekday())
  let (month_short, month_long) = month_names(dt.month())
  let weekday = match dt.weekday() {
    Monday => 1
    Tuesday => 2
    Wednesday => 3
    Thursday => 4
    Friday => 5
    Saturday => 6
    Sunday => 7
  }
  let chars = pattern.to_array()
  let out = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    i += 1
    if c != '%' {
      out.write_char(c)
      continue
    }
    guard i < chars.length() else { raise Invalid }
    let pad = if chars[i] is ('-' | '_' | '0') {
      let p = chars[i]
      i += 1
      Some(p)
    } else {
      None
    }
    guard i < chars.length() else { raise Invalid }
    let mut d = chars[i]
    i += 1
    let fraction = zero_pad(rem * 1_000_000, 9)
    if d is ('.' | '3' | '6' | '9') {
      if pad is Some(_) {
        raise Invalid
      }
      let dotted = d == '.'
      if dotted {
        guard i < chars.length() else { raise Invalid }
        d = chars[i]
        i += 1
      }
      let digits = if d == 'f' && dotted {
        if rem == 0 {
          0
        } else {
          3
        }
      } else {
        guard d is ('3' | '6' | '9') && i < chars.length() && chars[i] == 'f' else {
          raise Invalid
        }
        i += 1
        d.to_int() - '0'.to_int()
      }
      if dotted && digits > 0 {
        out.write_char('.')
      }
      out.write_stringview(fraction[:digits])
      continue
    }
    let numeric = match d {
      'Y' => Some((dt.year(), 4, '0'))
      'C' => Some((dt.year() / 100, 2, '0'))
      'y' => Some((dt.year() % 100, 2, '0'))
      'm' => Some((dt.month(), 2, '0'))
      'd' => Some((dt.day(), 2, '0'))
      'e' => Some((dt.day(), 2, ' '))
      'H' => Some((dt.hour(), 2, '0'))
      'k' => Some((dt.hour(), 2, ' '))
      'I' | 'l' =>
        Some(((dt.hour() + 11) % 12 + 1, 2, if d == 'l' { ' ' } else { '0' }))
      'M' => Some((dt.minute(), 2, '0'))
      'S' => Some((dt.second(), 2, '0'))
      'f' => Some((dt.nanosecond(), 9, '0'))
      'j' => Some((dt.ordinal(), 3, '0'))
      'w' => Some((weekday % 7, 1, '0'))
      'u' => Some((weekday, 1, '0'))
      'U' => Some(((dt.ordinal() + 6 - weekday % 7) / 7, 2, '0'))
      'W' => Some(((dt.ordinal() + 7 - weekday) / 7, 2, '0'))
      'q' => Some(((dt.month() - 1) / 3 + 1, 1, '0'))
      'G' | 'g' | 'V' => {
        let thursday = dt.to_plain_date().add_days((4 - weekday).to_int64()) catch {
            _ => raise OutOfRange
          }
        Some(
          if d == 'V' {
            ((thursday.ordinal() - 1) / 7 + 1, 2, '0')
          } else if d == 'G' {
            (thursday.year(), 4, '0')
          } else {
            (thursday.year() % 100, 2, '0')
          },
        )
      }
      _ => None
    }
    if numeric is Some((value, width, default_pad)) {
      let number = value.to_string()
      out.write_string(
        match pad {
          Some('-') => number
          Some('_') => number.pad_start(width, ' ')
          Some('0') => zero_pad(value, width)
          _ => number.pad_start(width, default_pad)
        },
      )
      continue
    }
    if pad is Some(_) && d != 's' {
      raise Invalid
    }
    let year = zero_pad(dt.year(), 4)
    let date = year +
      "-" +
      zero_pad(dt.month(), 2) +
      "-" +
      zero_pad(dt.day(), 2)
    let hm = zero_pad(dt.hour(), 2) + ":" + zero_pad(dt.minute(), 2)
    let hms = hm + ":" + zero_pad(dt.second(), 2)
    let us_date = zero_pad(dt.month(), 2) +
      "/" +
      zero_pad(dt.day(), 2) +
      "/" +
      zero_pad(dt.year() % 100, 2)
    let am = if dt.hour() < 12 { "AM" } else { "PM" }
    let text = match d {
      '%' => "%"
      't' => "\t"
      'n' => "\n"
      'F' => date
      'D' | 'x' => us_date
      'R' => hm
      'T' | 'X' => hms
      'p' => am
      'P' => am.to_lower()
      'r' =>
        zero_pad((dt.hour() + 11) % 12 + 1, 2) +
        ":" +
        zero_pad(dt.minute(), 2) +
        ":" +
        zero_pad(dt.second(), 2) +
        " " +
        am
      'b' | 'h' => month_short
      'B' => month_long
      'a' => day_short
      'A' => day_long
      'v' =>
        dt.day().to_string().pad_start(2, ' ') + "-" + month_short + "-" + year
      'c' =>
        day_short +
        " " +
        month_short +
        " " +
        dt.day().to_string().pad_start(2, ' ') +
        " " +
        hms +
        " " +
        year
      's' => seconds.to_string()
      'z' => offset_text(offset_seconds, false)
      'Z' => if utc { "UTC" } else { offset_text(offset_seconds, true) }
      '+' =>
        date +
        "T" +
        hms +
        (if rem == 0 { "" } else { "." + zero_pad(rem, 3) }) +
        offset_text(offset_seconds, true)
      ':' => {
        let mut count = 1
        while i < chars.length() && chars[i] == ':' {
          count += 1
          i += 1
        }
        guard count <= 3 && i < chars.length() && chars[i] == 'z' else {
          raise Invalid
        }
        i += 1
        let zone = offset_text(offset_seconds, true)
        if count == 2 {
          zone + ":" + zero_pad(offset_seconds.abs() % 60, 2)
        } else if count == 3 {
          zone[:3].to_owned()
        } else {
          zone
        }
      }
      '#' if i < chars.length() && chars[i] == 'z' => raise Unformattable
      _ => raise Invalid
    }
    out.write_string(text)
  }
  out.to_string()
}
