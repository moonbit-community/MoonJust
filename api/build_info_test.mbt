///|
test "release metadata is explicit" {
  assert_eq(@api.version(), "v0.1.0")
  assert_eq(@api.just_compatibility_target(), "1.57.0")
  assert_eq(@api.version_line(), "moonjust v0.1.0")
}

///|
fn parse_compat_version(text : String) -> (Int, Int, Int)? {
  let parts = text.split(".").collect()
  if parts.length() != 3 {
    return None
  }
  let values : Array[Int] = []
  for part in parts {
    if part.is_empty() || (part.length() > 1 && part[0] == '0') {
      return None
    }
    if part.length() > 9 {
      return None
    }
    let mut value = 0
    for character in part {
      if !character.is_ascii_digit() {
        return None
      }
      value = value * 10 + character.to_int() - 48
    }
    values.push(value)
  }
  match values {
    [major, minor, patch] => Some((major, minor, patch))
    _ => None
  }
}

///|
test "contract version parser accepts pinned semver and rejects malformed input" {
  assert_eq(parse_compat_version("0.0.0"), Some((0, 0, 0)))
  assert_eq(parse_compat_version("1.2.3"), Some((1, 2, 3)))
  assert_eq(parse_compat_version("999999999.0.0"), Some((999999999, 0, 0)))
  assert_eq(parse_compat_version("01.2.3"), None)
  assert_eq(parse_compat_version("1234567890.0.0"), None)
  assert_eq(parse_compat_version("foo"), None)
}

///|
test "contract version comparison is numeric and lexicographic" {
  let compare = fn(left : (Int, Int, Int), right : (Int, Int, Int)) -> Int {
    if left.0 != right.0 {
      left.0 - right.0
    } else if left.1 != right.1 {
      left.1 - right.1
    } else {
      left.2 - right.2
    }
  }
  assert_eq(compare((1, 2, 3), (1, 2, 3)), 0)
  assert_true(compare((1, 2, 3), (1, 2, 4)) < 0)
  assert_true(compare((1, 3, 0), (1, 2, 9)) > 0)
  assert_true(compare((2, 0, 0), (1, 99, 99)) > 0)
}

///|
test "contract current compatibility version is valid" {
  let version = parse_compat_version(@api.just_compatibility_target())
  assert_eq(version, Some((1, 57, 0)))
}
