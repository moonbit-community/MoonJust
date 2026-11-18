///|
test "upstream timestamps::format_string" {
  assert_eq(try! @datetime.format(0L, 0, "%H:%M:%S.%3f"), "00:00:00.000")
  assert_true(@planner.valid_timestamp_format("%H:%M:%S.%3f"))
}
