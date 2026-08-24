///|
fn is_combining(code : Int) -> Bool {
  (code >= 0x0300 && code <= 0x036f) ||
  (code >= 0x1ab0 && code <= 0x1aff) ||
  (code >= 0x1dc0 && code <= 0x1dff) ||
  (code >= 0x20d0 && code <= 0x20ff) ||
  (code >= 0xfe00 && code <= 0xfe0f) ||
  (code >= 0xfe20 && code <= 0xfe2f) ||
  (code >= 0xe0100 && code <= 0xe01ef) ||
  (code >= 0x1f3fb && code <= 0x1f3ff)
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
  let mut previous_wide = false
  let mut join_next = false
  let mut regional_pending = false
  for character in value {
    let code = character.to_int()
    if code == 9 {
      width += 1
    } else if code < 0x20 || (code >= 0x7f && code < 0xa0) || is_combining(code) {
      ()
    } else if code == 0x200d {
      join_next = true
    } else if code >= 0x1f1e6 && code <= 0x1f1ff {
      if regional_pending {
        regional_pending = false
      } else {
        width += 2
        regional_pending = true
      }
      previous_wide = true
      join_next = false
    } else if is_wide(code) {
      if !(join_next && previous_wide) {
        width += 2
      }
      previous_wide = true
      join_next = false
      regional_pending = false
    } else {
      width += 1
      previous_wide = false
      join_next = false
      regional_pending = false
    }
  }
  width
}
