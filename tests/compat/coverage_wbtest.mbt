///|
test "coverage outline requires exact location and test name" {
  let specs = parse_spec_index(
    "clean::tests::empty\tinternal/path/upstream_clean_test.mbt:14\tclean empty_path_maps_to_current_dir\tsrc/clean.rs:46\n",
  )
  let spec = specs["clean::tests::empty"]
  assert_true(
    outline_contains_spec(
      "   1. ZSeanYves/MoonJust/internal/path upstream_clean_test.mbt:14 index=0 name=\"clean empty_path_maps_to_current_dir\"",
      spec,
    ),
  )
  assert_false(
    outline_contains_spec(
      "   1. ZSeanYves/MoonJust/internal/path upstream_clean_test.mbt:14 index=0 name=\"clean empty_path_maps_to_current_dir changed\"",
      spec,
    ),
  )
}

///|
test "coverage index rejects malformed and duplicate evidence" {
  let invalid = "first\tinternal/path/a.mbt:2\ttest one\tsrc/a.rs:3\n" +
    "first\tinternal/path/b.mbt:4\ttest two\tsrc/b.rs:5\n" +
    "short\tinternal/path/c.mbt:6\tsrc/c.rs:7\n"
  let errors = spec_index_shape_errors(invalid)
  assert_true(errors.contains("duplicate spec-index upstream identity: first"))
  assert_true(
    errors.any(fn(error) {
      error.has_prefix("spec-index row must contain four tab-separated fields")
    }),
  )
}

///|
test "coverage normalizers reject malformed dynamic values" {
  assert_eq(normalize_uuid("not-a-uuid\n"), "not-a-uuid\n")
  assert_eq(normalize_datetime("2026-0x-03\n"), "2026-0x-03\n")
  assert_eq(normalize_timestamp("not-a-timestamp\n"), "not-a-timestamp\n")
  assert_eq(
    normalize_temp_path("/var/tmp/just-abcd/baz.txt\n"),
    "<TEMP_PATH>/baz.txt\n",
  )
  assert_eq(
    normalize_temp_path(
      "{\"source\":\"C:\\Users\\RUNNER~1\\AppData\\Local\\Temp\\moonjust-compat-candidate.42.abcd1234\\justfile\"}\n",
    ),
    "{\"source\":\"<CASE_ROOT>\\justfile\"}\n",
  )
  assert_eq(
    normalize_temp_path("unrelated C:\\Users\\winter\\file.txt value\n"),
    "unrelated C:\\Users\\winter\\file.txt value\n",
  )
}

///|
test "compatibility platform matching distinguishes Unix from Windows" {
  assert_true(platform_matches(Some("unix"), "linux"))
  assert_true(platform_matches(Some("unix"), "macos"))
  assert_false(platform_matches(Some("unix"), "windows"))
  assert_true(platform_matches(Some("windows"), "windows"))
  assert_false(platform_matches(Some("windows"), "linux"))
}

///|
async test "coverage rejects anchors outside exact test declarations" {
  let out_of_range : SpecCase = {
    fixture: "internal/path/upstream_clean_test.mbt:9999",
    anchor: "src/clean.rs:46",
    local_test: Some("clean empty_path_maps_to_current_dir"),
  }
  assert_true(
    validate_spec_anchor("clean::tests::empty", out_of_range)
    .unwrap_or("")
    .contains("out of range"),
  )
  let helper : SpecCase = {
    fixture: "internal/path/upstream_clean_test.mbt:2",
    anchor: "src/clean.rs:46",
    local_test: Some("clean empty_path_maps_to_current_dir"),
  }
  assert_true(
    validate_spec_anchor("clean::tests::empty", helper)
    .unwrap_or("")
    .contains("outside a test block"),
  )
  let wrong_name : SpecCase = {
    fixture: "internal/path/upstream_clean_test.mbt:14",
    anchor: "src/clean.rs:46",
    local_test: Some("wrong name"),
  }
  assert_true(
    validate_spec_anchor("clean::tests::empty", wrong_name)
    .unwrap_or("")
    .contains("name mismatch"),
  )
}

///|
test "source snapshots alone remain unclassified" {
  let metadata : Map[String, CaseMetadata] = Map([])
  let specs : Map[String, SpecCase] = Map([
    (
      "parser::snapshot",
      {
        fixture: "tests/compatibility/upstream/just-1.57.0/upstream-fixtures.txt:1",
        anchor: "src/parser.rs:1",
        local_test: None,
      },
    ),
  ])
  assert_eq(
    coverage_status("parser::snapshot", metadata, specs).0,
    "unclassified",
  )
}

///|
test "byte contract detects status output error tail and tree changes" {
  let metadata : CaseMetadata = {
    id: "test",
    cwd: "",
    platform: None,
    merged: false,
    live_prefix: None,
    live_timeout_ms: 1,
    normalizations: [],
    status: "match",
    compare: ["status", "stdout", "stderr", "tree"],
    allowed_difference: None,
    candidate_stdout_sha256: None,
    candidate_stderr_sha256: None,
    upstream_tests: [],
    upstream_anchors: [],
  }
  let expected : CaseResult = {
    status: 0,
    stdout: b"ok\n",
    stderr: b"error tail\n",
    merged: None,
    tree: b"file\t./out\t2\nok\n",
    live: true,
    steps: [{ status: 0, stdout: b"ok\n", stderr: b"error tail\n", }],
  }
  let actual : CaseResult = {
    status: 1,
    stdout: b"ox\n",
    stderr: b"error taiL\n",
    merged: None,
    tree: b"file\t./out\t3\nbad\n",
    live: true,
    steps: [{ status: 1, stdout: b"ox\n", stderr: b"error taiL\n", }],
  }
  assert_eq(difference_fields(expected, actual, metadata), [
    "status", "stdout", "stderr", "tree",
  ])
}

///|
async test "fixture audit rejects missing input and regex expectations" {
  let root = @fs.tmpdir(prefix="moonjust-contract-test")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  for
    file in [
      "compat-id", "expectation", "expected.status", "expected.stdout", "expected.stderr",
      "expected.tree",
    ] {
    @fs.write_file(join(root, file), b"")
  }
  let missing = fixture_structure_errors("case", root)
  assert_true(missing.any(fn(error) { error.contains("no explicit argv") }))
  @fs.write_file(join(root, "argv.txt"), b"")
  @fs.write_file(join(root, "stdout.regex"), b".*")
  let regex = fixture_structure_errors("case", root)
  assert_true(regex.any(fn(error) { error.contains("regex expectations") }))
}
