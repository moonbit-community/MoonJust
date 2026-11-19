///|
test "only a lowercase RFC variant v4 UUID occupies the entire normalized field" {
  let good = "b4679356-c8a0-42ba-8e74-db74ab700b98"
  let representative = "00000000-0000-4000-8000-000000000000"
  assert_eq(normalize_uuid(good), representative)
  assert_eq(normalize_uuid(good + "\n"), representative + "\n")
  for
    invalid in [
      "g4679356-c8a0-42ba-8e74-db74ab700b98",
      "B4679356-c8a0-42ba-8e74-db74ab700b98",
      "b4679356-c8a0-12ba-8e74-db74ab700b98",
      "b4679356-c8a0-42ba-7e74-db74ab700b98",
      "b4679356-c8a0-42ba-8e74-db74ab700b9-",
      good + "\n\n",
      "uuid=" + good,
      "<UUID>",
    ] {
    assert_eq(normalize_uuid(invalid), invalid)
    assert_not_eq(normalize_uuid(invalid), representative)
  }
  let raw = @utf8.encode(good)
  assert_eq(normalize_output(raw, "", "", [], stdout=true), raw)
  assert_eq(normalize_output(raw, "", "", ["uuid"]), raw)
}

///|
test "parallel alternatives preserve job serialization and dependency order" {
  let jobs = "a\na\nb\nb\n"
  let deps = "x\nb\nc\na\n"
  assert_eq(normalize_parallel_order("b\nb\na\na\n"), jobs)
  assert_eq(normalize_parallel_order("x\nc\nb\na\n"), deps)
  for
    invalid in [
      "a\nb\na\nb\n", "x\na\nc\nb\n", "b\nx\nc\na\n", "x\nb\na\n", "x\nb\nb\nc\na\n",
      "x\nc\nb\na", "x\nc\nb\na\nextra\n", "x\nc\nb\na\n\n",
    ] {
    assert_eq(normalize_parallel_order(invalid), invalid)
    assert_not_eq(normalize_parallel_order(invalid), jobs)
    assert_not_eq(normalize_parallel_order(invalid), deps)
  }
  let raw = b"x\nc\nb\na\n"
  assert_eq(normalize_output(raw, "", "", [], stdout=true), raw)
  assert_eq(normalize_output(raw, "", "", ["parallel-order"]), raw)
}

///|
test "timestamp normalization preserves command text and all readings in multi-command traces" {
  let single = "[23:59:59] echo one\n"
  assert_eq(normalize_timestamp(single), "[00:00:00] echo one\n")
  assert_eq(
    normalize_output(@utf8.encode(single), "", "", ["timestamp"], stdout=true),
    @utf8.encode(single),
  )
  for
    invalid in [
      "[24:01:00] echo one\n", "[12:60:00] echo one\n", "[12:00:60] echo one\n",
      "[<TIME>] echo one\n",
    ] {
    assert_eq(normalize_timestamp(invalid), invalid)
  }
  let advancing = "[12:00:01] first\n[12:00:02] second\n"
  let frozen = "[12:00:02] first\n[12:00:02] second\n"
  assert_eq(normalize_timestamp(advancing), advancing)
  assert_not_eq(normalize_timestamp(advancing), normalize_timestamp(frozen))
}
