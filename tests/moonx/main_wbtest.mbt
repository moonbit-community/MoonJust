///|
async test "MoonX candidate uses a direct argv prefix" {
  let candidate = prepare_candidate({
    candidate: "ZSeanYves/MoonJust@0.1.2",
    target: "wasm",
    suite: "smoke",
    official: "just",
  })
  assert_true(
    candidate.executable == "moonx" ||
    candidate.executable.to_lower().has_suffix(".exe"),
  )
  assert_eq(candidate.arguments(["--version"]), [
    "--target", "wasm", "ZSeanYves/MoonJust@0.1.2", "--version",
  ])
}

///|
test "aggregate report paths stop at the next option" {
  assert_eq(
    values_after(
      [
        "--suite", "aggregate", "--reports", "a.json", "b.json", "--report", "out.json",
      ],
      "--reports",
    ),
    ["a.json", "b.json"],
  )
}

///|
test "asset readiness diagnostics are distinct from functional failures" {
  assert_true(asset_not_ready(1, "404 asset not found"))
  assert_true(asset_not_ready(1, "download timed out"))
  assert_false(asset_not_ready(0, "download timed out"))
  assert_false(asset_not_ready(1, "unexpected version output"))
}

///|
test "JSON strings escape process output" {
  assert_eq(json_string("a\\b\n\"c\"\t"), "\"a\\\\b\\n\\\"c\\\"\\t\"")
}
