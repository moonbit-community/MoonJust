///|
test "upstream timestamps::format_string" {
  assert_true(@planner.valid_timestamp_format("%H:%M:%S.%3f"))
  assert_eq(@planner.format_timestamp(0L, "%H:%M:%S.%3f"), "00:00:00.000")
}
