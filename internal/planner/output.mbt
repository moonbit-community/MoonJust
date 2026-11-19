///|
fn color_code(color : CommandColor) -> String {
  match color {
    Bold => "1"
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
      "\u{001b}[" +
      (if value == Bold { "1" } else { "1;" + color_code(value) }) +
      "m" +
      text +
      "\u{001b}[0m"
    None => text
  }
}

///|
/// Return whether a command timestamp format only contains supported
/// strftime directives.
pub fn valid_timestamp_format(format : String) -> Bool {
  try @datetime.format(0L, 0, format) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
pub async fn[H : @host.HostClock] command_timestamp(
  host : H,
  format : String?,
) -> String? raise ExecutionError {
  guard format is Some(format) else { return None }
  let millis = @host.HostClock::now_millis(host) catch {
    error => raise Host(error)
  }
  let offset = @host.HostClock::local_offset_seconds(host, millis) catch {
    error => raise Host(error)
  }
  Some(
    @datetime.format(millis, offset, format) catch {
      error => raise InvalidTimestampFormat(error.message(format))
    },
  )
}

///|
pub async fn[H : @host.HostClock] script_timestamp(
  host : H,
  options : ExecutionOptions,
  format : String?,
  recipe : String,
) -> Bytes raise ExecutionError {
  match command_timestamp(host, format) {
    Some(value) =>
      @utf8.encode(
        "[" +
        paint_command(value, options.command_color()) +
        "] " +
        recipe +
        "\n",
      )
    None => b""
  }
}

///|
/// Render one command exactly as it is written to stderr.
pub fn render_command_echo(
  command : String,
  timestamp~ : String? = None,
  color~ : CommandColor? = None,
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
