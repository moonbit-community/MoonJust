///|
/// Install just's predefined expression constants without exporting them.
/// User assignments may overwrite these bindings during materialization.
pub fn install_constants(
  environment : Environment,
  flavor : @path.PathFlavor,
) -> Unit {
  for
    entry in [
      ("HEX", "0123456789abcdef"),
      ("HEXLOWER", "0123456789abcdef"),
      ("HEXUPPER", "0123456789ABCDEF"),
      ("CLEAR", "\u{001b}c"),
      ("NORMAL", "\u{001b}[0m"),
      ("BOLD", "\u{001b}[1m"),
      ("ITALIC", "\u{001b}[3m"),
      ("UNDERLINE", "\u{001b}[4m"),
      ("INVERT", "\u{001b}[7m"),
      ("HIDE", "\u{001b}[8m"),
      ("STRIKETHROUGH", "\u{001b}[9m"),
      ("BLACK", "\u{001b}[30m"),
      ("RED", "\u{001b}[31m"),
      ("GREEN", "\u{001b}[32m"),
      ("YELLOW", "\u{001b}[33m"),
      ("BLUE", "\u{001b}[34m"),
      ("MAGENTA", "\u{001b}[35m"),
      ("CYAN", "\u{001b}[36m"),
      ("WHITE", "\u{001b}[37m"),
      ("BG_BLACK", "\u{001b}[40m"),
      ("BG_RED", "\u{001b}[41m"),
      ("BG_GREEN", "\u{001b}[42m"),
      ("BG_YELLOW", "\u{001b}[43m"),
      ("BG_BLUE", "\u{001b}[44m"),
      ("BG_MAGENTA", "\u{001b}[45m"),
      ("BG_CYAN", "\u{001b}[46m"),
      ("BG_WHITE", "\u{001b}[47m"),
    ] {
    if !environment.contains(entry.0) {
      environment.set(entry.0, String(entry.1))
    }
  }
  if !environment.contains("PATH_SEP") {
    environment.set(
      "PATH_SEP",
      String(if flavor == Windows { "\\" } else { "/" }),
    )
  }
  if !environment.contains("PATH_VAR_SEP") {
    environment.set(
      "PATH_VAR_SEP",
      String(if flavor == Windows { ";" } else { ":" }),
    )
  }
}
