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
      error.has_prefix("spec-index row must contain four fields")
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
    normalize_temp_path(
      "/c/Users/RUNNER~1/AppData/Local/Temp/moonjust-compat-official.42.abcd1234\n",
    ),
    "<CASE_ROOT>\n",
  )
  assert_eq(
    normalize_temp_path(
      "C:\\Users\\runneradmin\\AppData\\Local\\Temp\\moonjust-compat-candidate.42.abcd1234\\bar.just:1:4\n",
    ),
    "<CASE_ROOT>\\bar.just:1:4\n",
  )
  assert_eq(
    normalize_temp_path(
      "C:/Users/RUNNER~1/AppData/Local/Temp/moonjust-compat-candidate.42.abcd1234/foo/baz\n",
    ),
    "<CASE_ROOT>/foo/baz\n",
  )
  assert_eq(
    normalize_temp_path("unrelated C:\\Users\\winter\\file.txt value\n"),
    "unrelated C:\\Users\\winter\\file.txt value\n",
  )
}

///|
test "Windows symlink targets resolve from the link parent" {
  assert_eq(
    symlink_target("C:/fixture", "sub/justfile", "../src", "windows").replace_all(
      old="\\",
      new="/",
    ),
    "C:/fixture/src",
  )
}

///|
test "canonical path normalization only folds declared path syntax" {
  assert_eq(
    normalize_canonical_path("\\\\?\\<CASE_ROOT>\\foo\\baz\n"),
    "<CASE_ROOT>/foo/baz\n",
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
    smoke_scope: None,
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
    smoke_scope: None,
    local_test: Some("clean empty_path_maps_to_current_dir"),
  }
  assert_true(
    validate_spec_anchor("clean::tests::empty", helper)
    .unwrap_or("")
    .contains("not a test declaration"),
  )
  let wrong_name : SpecCase = {
    fixture: "internal/path/upstream_clean_test.mbt:14",
    anchor: "src/clean.rs:46",
    smoke_scope: None,
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
        smoke_scope: None,
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
    closed_stdout: false,
    verify_snapshot: false,
    live_prefix: None,
    live_timeout_ms: 1,
    normalizations: [],
    status: "match",
    compare: ["status", "stdout", "stderr", "tree"],
    allowed_difference: None,
    candidate_stdout_sha256: None,
    upstream_tests: [],
    host_inputs: [],
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
  defer (@fs.remove(root, recursive=true) catch { _ => () })
  for
    file in [
      "compat-id", "expectation", "expected.status", "expected.stdout", "expected.stderr",
      "expected.tree",
    ] {
    @fs.write_binary(join(root, file), b"")
  }
  let missing = fixture_structure_errors("case", root)
  assert_true(missing.any(fn(error) { error.contains("no explicit argv") }))
  @fs.write_binary(join(root, "argv.txt"), b"")
  @fs.write_binary(join(root, "stdout.regex"), b".*")
  let regex = fixture_structure_errors("case", root)
  assert_true(regex.any(fn(error) { error.contains("regex expectations") }))
}

///|
test "allowlisted formatting must refuse unchanged, not just return a known code" {
  let fixture = "148-indentation-setting-format"
  let manifest =
    #|[[case]]
    #|id = "MJ-COMPAT-0148"
    #|directory = "148-indentation-setting-format"
    #|allowed_difference = "atomic-format-permissions"
    #|upstream_tests = ["format::indentation_setting_format"]
  let details = parse_manifest(manifest).cases[fixture]
  let oracle : CaseResult = {
    status: 0,
    stdout: b"",
    stderr: b"",
    merged: None,
    tree: b"new",
    live: true,
    steps: [],
  }
  let refusal = {
    ..oracle,
    status: 1,
    tree: b"old",
    stderr: b"error: host operation failed: InvalidInput(\"cannot atomically replace an existing file and preserve its permissions\")\n",
  }
  let fields = ["status", "stderr", "tree"]
  fn allowed(result : CaseResult) -> Bool {
    expected_difference_allowed(
      fixture, fields, result, oracle, b"old", details,
    )
  }
  assert_true(allowed(refusal))
  assert_false(allowed({ ..refusal, tree: b"changed", }))
  assert_false(allowed({ ..refusal, stderr: b"different failure", }))
  assert_false(allowed(oracle))
  assert_true(refusal_digest("unrelated", details) is None)
  assert_true(
    refusal_digest(fixture, { ..details, platform: Some("unix"), }) is None,
  )
}

///|
async test "schema 5 distinguishes document contracts, local smoke and repository evidence" {
  let specs = parse_spec_index(
    @fs.read_text("tests/compatibility/upstream/just-1.59.0/spec-index.txt"),
  )
  let readme = "readme::readme"
  let completion = "config::tests::subcommand_conflict_completions"
  let repository = "readme::h1_and_h2_headings_are_setext"
  let names = Set([readme, completion, repository])
  let empty : Set[String] = Set([])
  // An outline entry cannot stand in for running the document oracle.
  let report = coverage_report(
    names,
    Map([]),
    specs,
    empty,
    empty,
    empty,
    empty,
    empty,
    names,
    empty,
    failures=0,
    product_identity=0,
    platform="macos",
    target="wasm",
    reentry="",
  )
  assert_false(report.complete(allow_deferred=true))
  assert_eq(report.document_oracle_declared, 1)
  assert_eq(report.document_oracle_executed, 0)
  assert_eq(report.moonbit_spec_executed, 0)
  assert_eq(report.local_smoke_executed, 1)
  assert_eq(report.repository_only, 1)
  for row in report.rows {
    if row.upstream_id == completion {
      assert_eq(row.status, "local-smoke")
      assert_true(row.evidence_scope.contains("Unsupported"))
      assert_eq(row.local_test, "upstream " + completion)
    } else if row.upstream_id == repository {
      assert_eq(row.execution_state, "excluded")
      assert_eq(row.local_test, "")
    } else {
      assert_eq(row.status, "document-oracle")
      assert_eq(row.execution_state, "unexecuted")
    }
  }
}

///|
test "README document oracle extracts only closed just fences and keeps body lines" {
  assert_eq(
    readme_just_blocks(
      "# Title\n```sh\njust abc\n```\n```just\nx:\n  echo x\n\n```",
    ),
    [(5, "x:\n  echo x\n\n")],
  )
  let invalid = Some(readme_just_blocks("```just\nfoo:\n")) catch { _ => None }
  assert_true(invalid is None)
}

///|
async test "snapshot provenance is bound to its indexed line" {
  let raw = "man::output\ttests/compatibility/upstream/just-1.57.0/upstream-fixtures.txt:1\t\ttests/man.rs:4"
  let spec = parse_spec_index(raw)["man::output"]
  assert_false(audited_fixture("man::output", spec, Map([])))
}

///|
async test "all completion and signal exclusions carry verified pinned source anchors" {
  let specs = parse_spec_index(
    @fs.read_text("tests/compatibility/upstream/just-1.59.0/spec-index.txt"),
  )
  let names = upstream_test_names(
    @fs.read_text("tests/compatibility/upstream/just-1.59.0/test-list.txt"),
  )
  let mut completions = 0
  let mut signals = 0
  for id in names {
    guard exclusion(id) is Some((kind, _)) else { continue }
    let (status, _, anchor, _) = coverage_status(id, Map([]), specs)
    assert_eq(status, kind, msg=id)
    assert_eq(validate_upstream_anchor(id, anchor), None, msg=id)
    if status == "excluded-completion" {
      completions += 1
    } else {
      signals += 1
    }
  }
  assert_eq(completions, 39)
  assert_eq(signals, 21)
}
