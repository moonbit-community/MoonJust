///|
fn usage() -> String {
  "Usage: moonjust-compat --candidate PATH --official PATH " +
  "[--candidate-runner PATH] " +
  "[--cases PATH] [--manifest PATH] [--upstream-list PATH] " +
  "[--record-expected] [--verify-snapshots] [--strict-coverage] " +
  "[--allow-deferred-platform] [--wasm-reentry PATH]"
}

///|
fn option(args : ArrayView[String], name : String) -> String? {
  for index, value in args {
    if value == name && index + 1 < args.length() {
      return Some(args[index + 1])
    }
  }
  None
}

///|
fn has_flag(args : ArrayView[String], name : String) -> Bool {
  for value in args {
    if value == name {
      return true
    }
  }
  false
}

///|
async fn main {
  let args = @env.args()[1:]
  guard option(args, "--candidate") is Some(candidate_value) &&
    option(args, "--official") is Some(official_value) else {
    @stdio.stderr.text.write(usage() + "\n")
    @env.exit(2)
    return
  }
  let cases_root = option(args, "--cases").unwrap_or("tests/differential/cases")
  let selected_case = option(args, "--case")
  let record_expected = has_flag(args, "--record-expected")
  let verify_snapshots = has_flag(args, "--verify-snapshots")
  let manifest = option(args, "--manifest").unwrap_or(
    "tests/differential/cases.toml",
  )
  let upstream_list = option(args, "--upstream-list").unwrap_or(
    "tests/compatibility/upstream/just-1.57.0/test-list.txt",
  )
  let report_path = option(args, "--coverage-report")
  let execution_target = option(args, "--execution-target").unwrap_or("wasm")
  let spec_text = read_text(
    option(args, "--spec-index").unwrap_or(
      "tests/compatibility/upstream/just-1.57.0/spec-index.txt",
    ),
  )
  let spec_index = parse_spec_index(spec_text)
  let candidate_runner = option(args, "--candidate-runner").unwrap_or("")
  let candidate = @testkit.prepare_program(
    candidate_value,
    runner=candidate_runner,
  )
  let official = @testkit.prepare_program(official_value)
  let parsed_manifest = parse_manifest(read_text(manifest))
  let metadata = parsed_manifest.cases
  let upstream_names = upstream_test_names(read_text(upstream_list))
  let mut matched = 0
  let mut known = 0
  let mut product_identity = 0
  let mut selected_found = false
  let failures : Array[String] = []
  let executed : Set[String] = Set([])
  let exact : Set[String] = Set([])
  let known_upstream : Set[String] = Set([])
  let failed_upstream : Set[String] = Set([])
  let deferred : Set[String] = Set([])
  // MoonBit specs run under `moon test`; this set is populated only by an
  // explicit external execution report, never inferred from the index.
  let spec_executed : Set[String] = if has_flag(args, "--strict-coverage") {
    execute_moonbit_specs(spec_index, failures)
  } else {
    Set([])
  }
  let platform = @testkit.runner_os()
  let (architecture, cpu_count) = if platform == "windows" {
    (
      @env.get_env_var("PROCESSOR_ARCHITECTURE").unwrap_or(""),
      @env.get_env_var("NUMBER_OF_PROCESSORS").unwrap_or(""),
    )
  } else {
    (
      unix_host_fact("uname", "-m"),
      unix_host_fact("getconf", "_NPROCESSORS_ONLN"),
    )
  }
  let wasm_reentry = match option(args, "--wasm-reentry") {
    Some(path) if !path.is_empty() => @fs.realpath(path)
    _ => ""
  }
  if execution_target != "wasm" {
    failures.push("execution target must be `wasm`")
  }
  if option(args, "--candidate-runner") is None {
    failures.push("Wasm compatibility requires --candidate-runner")
  }
  let expected_version = module_version(read_text("moon.mod"))
  match expected_version {
    Some(version) if candidate_version_matches(candidate, version) => ()
    Some(version) =>
      failures.push(
        "candidate --version does not match moon.mod (expected moonjust v" +
        version +
        ")",
      )
    None => failures.push("moon.mod does not declare a product version")
  }
  if !official_is_pinned(official) {
    failures.push("official oracle must report exactly `just 1.57.0`")
  }
  validate_inventory(
    parsed_manifest, cases_root, upstream_names, spec_index, spec_text, failures,
  )
  let documents_passed : Set[String] = Set([])
  for id in upstream_names {
    guard document_contract(id) is Some(contract) &&
      !(contract is RepositoryOnly(_)) else {
      continue
    }
    if selected_case is Some(name) && name != id {
      continue
    }
    selected_found = true
    try check_document(contract, official, candidate) catch {
      error => {
        failed_upstream.add(id)
        failures.push(id + ": " + error.to_string())
      }
    } noraise {
      _ => {
        documents_passed.add(id)
        @stdio.stdout.text.write("PASS  " + id + "\n")
      }
    }
  }
  for name in @fs.readdir(cases_root, include_hidden=false, sort=true) {
    if selected_case is Some(selected) && name != selected {
      continue
    }
    selected_found = true
    let case_dir = join(cases_root, name)
    if @fs.kind(case_dir) != Directory {
      continue
    }
    let details = metadata
      .get(name)
      .unwrap_or({
        cwd: "",
        platform: None,
        merged: false,
        live_prefix: None,
        live_timeout_ms: 1000,
        id: "",
        status: "match",
        compare: ["status", "stdout", "stderr", "tree"],
        allowed_difference: None,
        candidate_stdout_sha256: None,
        host_inputs: [],
        upstream_tests: [],
        upstream_anchors: [],
        normalizations: [],
      })
    if details.id.is_empty() {
      failures.push(name + ": missing manifest identity")
      continue
    }
    let compat_id = read_text(join(case_dir, "compat-id")).trim().to_owned()
    if compat_id != details.id {
      failures.push(
        name +
        ": manifest id " +
        details.id +
        " does not match compat-id " +
        compat_id,
      )
      continue
    }
    if !platform_matches(details.platform, platform) {
      for upstream_test in details.upstream_tests {
        deferred.add(upstream_test)
      }
      @stdio.stdout.text.write(
        "SKIP  " + name + " (platform=" + details.platform.unwrap_or("") + ")\n",
      )
      continue
    }
    let stdout_regex = @fs.exists(join(case_dir, "stdout.regex"))
    let stderr_regex = @fs.exists(join(case_dir, "stderr.regex"))
    if stdout_regex || stderr_regex {
      failures.push(
        name + ": regex expectations are forbidden; use exact bytes",
      )
      for upstream_test in details.upstream_tests {
        failed_upstream.add(upstream_test)
      }
      continue
    }
    let official_result = run_side(
      official, case_dir, details, "official", architecture, cpu_count, "", platform,
    )
    for upstream_test in details.upstream_tests {
      executed.add(upstream_test)
    }
    if record_expected {
      write_expected(case_dir, official_result)
    }
    let expected_snapshot_result = expected_snapshot(case_dir).map(fn(
      snapshot,
    ) {
      normalize_snapshot(snapshot, official.subject(), details.normalizations)
    })
    match expected_snapshot_result {
      Some(snapshot) if verify_snapshots && !record_expected => {
        let snapshot_differences = difference_fields(
          snapshot, official_result, details,
        )
        if !snapshot_differences.is_empty() {
          failures.push(
            name +
            ": recorded official result differs in [" +
            snapshot_differences.join(", ") +
            "]",
          )
        }
      }
      Some(_) => ()
      None => failures.push(name + ": missing expected result snapshot")
    }
    // The live official oracle is authoritative on every runner. Recorded
    // snapshots document the fixture and are optionally audited on the same
    // platform with --verify-snapshots.
    let expected = official_result
    let initial_tree = Ref(b"")
    let actual = run_side(
      candidate,
      case_dir,
      details,
      "candidate",
      architecture,
      cpu_count,
      wasm_reentry,
      platform,
      initial_tree?=if details.allowed_difference ==
        Some("atomic-format-permissions") {
        Some(initial_tree)
      } else {
        None
      },
    )
    let differences = difference_fields(expected, actual, details)
    let expectation = read_text(join(case_dir, "expectation")).trim().to_owned()
    let expected_status = if details.status == "expected-difference" {
      "difference"
    } else {
      "match"
    }
    if expectation != expected_status {
      failures.push(
        name +
        ": expectation file says " +
        expectation +
        ", manifest says " +
        expected_status,
      )
    } else if expectation == "match" && differences.is_empty() {
      matched += 1
      for upstream_test in details.upstream_tests {
        exact.add(upstream_test)
      }
      @stdio.stdout.text.write("PASS  " + name + "\n")
    } else if expectation == "difference" &&
      expected_difference_allowed(
        name,
        differences,
        actual,
        expected,
        initial_tree.val,
        details,
      ) {
      if details.allowed_difference == Some("product-identity") {
        product_identity += 1
      } else {
        known += 1
        for upstream_test in details.upstream_tests {
          known_upstream.add(upstream_test)
        }
      }
      @stdio.stdout.text.write(
        "XDIFF " + name + " [" + differences.join(", ") + "]\n",
      )
    } else {
      write_difference_details(name, differences, expected, actual)
      for upstream_test in details.upstream_tests {
        failed_upstream.add(upstream_test)
      }
      failures.push(
        name +
        ": expected " +
        expectation +
        ", differing fields [" +
        differences.join(", ") +
        "]",
      )
    }
  }
  if selected_case is Some(selected) && !selected_found {
    failures.push("requested case does not exist: " + selected)
  }
  let report = coverage_report(
    upstream_names,
    metadata,
    spec_index,
    executed,
    exact,
    known_upstream,
    failed_upstream,
    deferred,
    spec_executed,
    documents_passed,
    failures=failures.length(),
    product_identity~,
    platform~,
    target=execution_target,
    reentry=if wasm_reentry.is_empty() {
      "not provided"
    } else {
      "test launcher"
    },
  )
  if has_flag(args, "--strict-coverage") &&
    !report.complete(allow_deferred=has_flag(args, "--allow-deferred-platform")) {
    failures.push("upstream coverage is incomplete")
    report.failures += 1
  }
  if report_path is Some(path) {
    @fs.write_text(path, ToJson::to_json(report).stringify() + "\n")
  }
  for failure in failures {
    @stdio.stderr.text.write("FAIL  " + failure + "\n")
  }
  @stdio.stdout.text.write(
    "matched=\{matched} known_differences=\{known} product_identity_difference=\{product_identity} failures=\{report.failures}" +
    " upstream_total=\{report.upstream_total} differential_declared=\{report.differential_declared}" +
    " differential_executed=\{report.differential_executed} differential_exact=\{report.differential_exact}" +
    " differential_known_difference=\{report.differential_known_difference} moonbit_spec_executed=\{report.moonbit_spec_executed}" +
    " local_smoke_executed=\{report.local_smoke_executed} document_oracle_executed=\{report.document_oracle_executed}" +
    " repository_only=\{report.repository_only} excluded_completion=\{report.excluded_completion}" +
    " excluded_signal=\{report.excluded_signal} deferred_platform=\{report.deferred_platform} unclassified=\{report.unclassified}\n",
  )
  if !failures.is_empty() {
    @env.exit(1)
  }
}
