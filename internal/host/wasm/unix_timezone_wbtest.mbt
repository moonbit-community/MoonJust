///|
test "POSIX TZ offsets use seconds east of UTC at the requested instant" {
  fn offset(rule : String, second : Int64) -> Int32 {
    try! @time.ZonedDateTime::from_unix_second(
      second,
      zone=posix_zone(rule).unwrap(),
    )
    .offset()
    .seconds()
  }
  assert_eq(offset("UTC+5", 0L), -18000)
  assert_eq(offset("<NPT>-5:45", 0L), 20700)
  assert_eq(offset("XXX0:00:30", 0L), -30)
  let us = "EST5EDT,M3.2.0/2,M11.1.0/2"
  assert_eq(offset(us, 1710053999L), -18000)
  assert_eq(offset(us, 1710054000L), -14400)
  assert_eq(offset(us, 1730613599L), -14400)
  assert_eq(offset(us, 1730613600L), -18000)
  for name in ["Asia/Shanghai", ":UTC+5", "/etc/localtime", "UTC+5junk"] {
    assert_true(posix_zone(name) is None)
  }
}
