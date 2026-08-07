///|
fn is_combining(code : Int) -> Bool {
  (code >= 0x0300 && code <= 0x036f) ||
  (code >= 0x1ab0 && code <= 0x1aff) ||
  (code >= 0x1dc0 && code <= 0x1dff) ||
  (code >= 0x20d0 && code <= 0x20ff) ||
  (code >= 0xfe20 && code <= 0xfe2f)
}

///|
fn is_wide(code : Int) -> Bool {
  (code >= 0x1100 && code <= 0x115f) ||
  (code >= 0x2329 && code <= 0x232a) ||
  (code >= 0x2e80 && code <= 0xa4cf) ||
  (code >= 0xac00 && code <= 0xd7a3) ||
  (code >= 0xf900 && code <= 0xfaff) ||
  (code >= 0xfe10 && code <= 0xfe19) ||
  (code >= 0xfe30 && code <= 0xfe6f) ||
  (code >= 0xff00 && code <= 0xff60) ||
  (code >= 0xffe0 && code <= 0xffe6) ||
  (code >= 0x1f300 && code <= 0x1faff) ||
  (code >= 0x20000 && code <= 0x3fffd)
}

///|
fn display_width(value : String) -> Int {
  let mut width = 0
  for character in value {
    let code = character.to_int()
    if is_combining(code) {
      ()
    } else if is_wide(code) {
      width += 2
    } else {
      width += 1
    }
  }
  width
}
