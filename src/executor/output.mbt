///|
fn color_code(color : CommandColor) -> String {
  match color {
    Black => "30"
    Red => "31"
    Green => "32"
    Yellow => "33"
    Blue => "34"
    Magenta => "35"
    Cyan => "36"
    White => "37"
  }
}

///|
fn paint_command(text : String, color : CommandColor?) -> String {
  match color {
    Some(value) =>
      "\u{001b}[1;" + color_code(value) + "m" + text + "\u{001b}[0m"
    None => text
  }
}

///|
/// Format a UTC command timestamp without exposing host-specific time types.
/// Unsupported directives are retained literally so diagnostics stay stable.
pub fn format_timestamp(millis : Int64, format : String) -> String {
  let mut seconds = millis / 1000L
  let mut remainder = (millis % 1000L).to_int()
  if remainder < 0 {
    seconds -= 1L
    remainder += 1000
  }
  let datetime = @time.PlainDateTime::from_unix_second(
    seconds,
    remainder * 1_000_000,
    @time.utc_offset,
  ) catch {
    _ => return millis.to_string()
  }
  let values = format.to_array()
  let output = StringBuilder()
  let mut index = 0
  while index < values.length() {
    if values[index] != '%' || index + 1 >= values.length() {
      output.write_char(values[index])
      index += 1
      continue
    }
    let directive = values[index + 1]
    match directive {
      '%' => output.write_char('%')
      'Y' => output.write_string(datetime.year().to_string().pad_start(4, '0'))
      'm' => output.write_string(datetime.month().to_string().pad_start(2, '0'))
      'd' => output.write_string(datetime.day().to_string().pad_start(2, '0'))
      'H' => output.write_string(datetime.hour().to_string().pad_start(2, '0'))
      'M' =>
        output.write_string(datetime.minute().to_string().pad_start(2, '0'))
      'S' =>
        output.write_string(datetime.second().to_string().pad_start(2, '0'))
      'f' =>
        output.write_string(datetime.nanosecond().to_string().pad_start(9, '0'))
      's' => output.write_string(seconds.to_string())
      _ => {
        output.write_char('%')
        output.write_char(directive)
      }
    }
    index += 2
  }
  output.to_string()
}

///|
/// Render one command exactly as it is written to stderr.
pub fn render_command_echo(
  command : String,
  timestamp? : String? = None,
  color? : CommandColor? = None,
) -> Bytes {
  let prefix = match timestamp {
    Some(value) => "[" + paint_command(value, color) + "] "
    None => ""
  }
  @utf8.encode(prefix + paint_command(command, color) + "\n")
}

///|
/// Render the stable `--time` completion message from monotonic milliseconds.
pub fn render_elapsed_message(recipe : String, elapsed_millis : Int64) -> Bytes {
  let safe = Int64::max(0L, elapsed_millis)
  let seconds = safe / 1000L
  let fraction = (safe % 1000L).to_int().to_string()
  let padded = match fraction.length() {
    1 => "00" + fraction
    2 => "0" + fraction
    _ => fraction
  }
  @utf8.encode(
    "---> " +
    recipe +
    " completed in " +
    seconds.to_string() +
    "." +
    padded +
    "s\n",
  )
}

///|
pub fn render_failure_message(error : ExecutionError, show : Bool) -> Bytes {
  if show {
    @utf8.encode(error.message() + "\n")
  } else {
    b""
  }
}
