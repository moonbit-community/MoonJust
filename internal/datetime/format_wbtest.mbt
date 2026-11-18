///|
test "calendar dates, ISO week years, fractions and offsets use the same instant" {
  assert_eq(
    try! format(-1L, 0, "%F %T%.3f %s", utc=true),
    "1969-12-31 23:59:59.999 -1",
  )
  assert_eq(
    try! format(0L, 20700, "%F %R %z %:z %Z"),
    "1970-01-01 05:45 +0545 +05:45 +05:45",
  )
  assert_eq(
    try! format(1609459200000L, 0, "%G-W%V-%u %F %j", utc=true),
    "2020-W53-5 2021-01-01 001",
  )
}
