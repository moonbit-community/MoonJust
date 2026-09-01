///|
struct UpstreamStyleHost {}

///|
impl @host.HostTerminal for UpstreamStyleHost with fn terminal_info(_self) -> @host.TerminalInfo raise @host.HostError {
  @host.TerminalInfo::new(true, true, true, true)
}

///|
fn upstream_style(
  styles : Array[String],
  text? : String,
  color_mode? : String,
) -> String raise EvaluationError {
  let arguments : Array[@value.Value] = []
  if styles.length() == 1 {
    arguments.push(@value.Value::String(styles[0]))
  } else {
    arguments.push(
      @value.Value::List(styles.map(fn(style) { @value.Value::String(style) })),
    )
  }
  match text {
    Some(value) => arguments.push(@value.Value::String(value))
    None => ()
  }
  style_value(
    UpstreamStyleHost::{ },
    arguments,
    EvaluationContext::new(lists=styles.length() > 1, color_mode?),
    @source.Span::origin(@source.SourceId::new(950)),
  ).to_string()
}

///|
test "upstream style::style_single" {
  for
    pair in [
      ("black", "30"),
      ("blue", "34"),
      ("cyan", "36"),
      ("green", "32"),
      ("magenta", "35"),
      ("red", "31"),
      ("white", "37"),
      ("yellow", "33"),
      ("fg:black", "30"),
      ("fg:blue", "34"),
      ("bg:black", "40"),
      ("bg:blue", "44"),
      ("bold", "1"),
      ("dim", "2"),
      ("italic", "3"),
      ("underline", "4"),
      ("blink", "5"),
      ("reverse", "7"),
      ("hidden", "8"),
      ("strikethrough", "9"),
    ] {
    assert_eq(
      try! upstream_style([pair.0], text="foo"),
      "\u{001b}[" + pair.1 + "mfoo\u{001b}[0m",
    )
  }
}

///|
test "upstream style::style_fixed" {
  for
    pair in [
      ("0", "38;5;0"),
      ("255", "38;5;255"),
      ("fg:5", "38;5;5"),
      ("bg:200", "48;5;200"),
    ] {
    assert_eq(
      try! upstream_style([pair.0], text="foo"),
      "\u{001b}[" + pair.1 + "mfoo\u{001b}[0m",
    )
  }
}

///|
test "upstream style::style_rgb" {
  for
    pair in [
      ("#ff8800", "38;2;255;136;0"),
      ("fg:#ff8800", "38;2;255;136;0"),
      ("bg:#04b575", "48;2;4;181;117"),
      ("#abc", "38;2;170;187;204"),
      ("fg:#abc", "38;2;170;187;204"),
      ("bg:#f0a", "48;2;255;0;170"),
    ] {
    assert_eq(
      try! upstream_style([pair.0], text="foo"),
      "\u{001b}[" + pair.1 + "mfoo\u{001b}[0m",
    )
  }
}

///|
test "upstream style::style_stream" {
  assert_eq(
    try! upstream_style(["red", "stdout"], text="foo", color_mode="always"),
    "\u{001b}[31mfoo\u{001b}[0m",
  )
  assert_eq(
    try! upstream_style(["red", "stdout"], text="foo", color_mode="never"),
    "foo",
  )
}

///|
test "upstream style::style_prefix_without_text" {
  assert_eq(try! upstream_style(["red"]), "\u{001b}[31m")
}

///|
test "upstream style::style_with_text" {
  assert_eq(
    try! upstream_style(["error"], text="foo"),
    "\u{001b}[1;31mfoo\u{001b}[0m",
  )
}
