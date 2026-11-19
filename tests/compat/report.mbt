///|
#derive(ToJson)
priv struct CoverageRow {
  upstream_id : String
  evidence_kind : String
  execution_state : String
  status : String
  execution_platform : String
  execution_target : String
  required_platform : String
  fixture : String
  host_inputs : Array[String]
  local_test : String
  upstream_source_anchor : String
  evidence_scope : String
  difference_reason : String
  candidate_digest : String
}

///|
#derive(ToJson)
priv struct CoverageReport {
  schema_version : Int32
  runner_os : String
  target : String
  reentry : String
  upstream_total : Int32
  mut differential_declared : Int32
  mut differential_executed : Int32
  mut differential_exact : Int32
  mut differential_known_difference : Int32
  mut moonbit_spec_declared : Int32
  mut moonbit_spec_executed : Int32
  mut local_smoke_declared : Int32
  mut local_smoke_executed : Int32
  mut document_oracle_declared : Int32
  mut document_oracle_executed : Int32
  mut repository_only : Int32
  mut excluded_completion : Int32
  mut excluded_signal : Int32
  deferred_platform : Int32
  mut unclassified : Int32
  mut failures : Int32
  product_identity_difference : Int32
  rows : Array[CoverageRow]
}

///|
fn coverage_report(
  upstream_names : Set[String],
  metadata : Map[String, CaseMetadata],
  specs : Map[String, SpecCase],
  executed : Set[String],
  exact : Set[String],
  known : Set[String],
  failed : Set[String],
  deferred : Set[String],
  spec_executed : Set[String],
  documents_passed : Set[String],
  failures~ : Int32,
  product_identity~ : Int32,
  platform~ : String,
  target~ : String,
  reentry~ : String,
) -> CoverageReport {
  let report : CoverageReport = {
    schema_version: 4,
    runner_os: platform,
    target,
    reentry,
    upstream_total: upstream_names.length(),
    differential_declared: 0,
    differential_executed: 0,
    differential_exact: 0,
    differential_known_difference: 0,
    moonbit_spec_declared: 0,
    moonbit_spec_executed: 0,
    local_smoke_declared: 0,
    local_smoke_executed: 0,
    document_oracle_declared: 0,
    document_oracle_executed: 0,
    repository_only: 0,
    excluded_completion: 0,
    excluded_signal: 0,
    deferred_platform: deferred.length(),
    unclassified: 0,
    failures,
    product_identity_difference: product_identity,
    rows: [],
  }
  for upstream_id in upstream_names {
    let (status, fixture, anchor, scope) = coverage_status(
      upstream_id, metadata, specs,
    )
    let differential = status == "differential-exact" ||
      status == "differential-known-difference"
    let details = if differential { metadata.get(fixture) } else { None }
    let state = if failed.contains(upstream_id) {
      "failed"
    } else if deferred.contains(upstream_id) {
      "deferred-platform"
    } else {
      match status {
        "repository-only" | "excluded-completion" | "excluded-signal" =>
          "excluded"
        "document-oracle" if documents_passed.contains(upstream_id) =>
          "executed"
        "moonbit-spec" | "local-smoke" if spec_executed.contains(upstream_id) =>
          "executed"
        "differential-exact" if exact.contains(upstream_id) => "executed"
        "differential-known-difference" if known.contains(upstream_id) =>
          "executed"
        _ => "unexecuted"
      }
    }
    if differential {
      report.differential_declared += 1
      if executed.contains(upstream_id) {
        report.differential_executed += 1
      }
    }
    match status {
      "differential-exact" =>
        if state == "executed" {
          report.differential_exact += 1
        }
      "differential-known-difference" =>
        if state == "executed" {
          report.differential_known_difference += 1
        }
      "moonbit-spec" => {
        report.moonbit_spec_declared += 1
        if state == "executed" {
          report.moonbit_spec_executed += 1
        }
      }
      "local-smoke" => {
        report.local_smoke_declared += 1
        if state == "executed" {
          report.local_smoke_executed += 1
        }
      }
      "document-oracle" => {
        report.document_oracle_declared += 1
        if state == "executed" {
          report.document_oracle_executed += 1
        }
      }
      "repository-only" => report.repository_only += 1
      "excluded-completion" => report.excluded_completion += 1
      "excluded-signal" => report.excluded_signal += 1
      _ => report.unclassified += 1
    }
    report.rows.push({
      upstream_id,
      status,
      evidence_kind: if differential {
        "differential"
      } else {
        status
      },
      execution_state: state,
      execution_platform: platform,
      execution_target: target,
      required_platform: details.bind(d => d.platform).unwrap_or("all"),
      host_inputs: details.map(d => d.host_inputs).unwrap_or([]),
      fixture,
      local_test: if status == "moonbit-spec" || status == "local-smoke" {
        specs[upstream_id].local_test.unwrap_or("")
      } else {
        ""
      },
      upstream_source_anchor: anchor,
      evidence_scope: if differential {
        ""
      } else {
        scope
      },
      difference_reason: if status == "differential-known-difference" {
        scope
      } else {
        ""
      },
      candidate_digest: if status == "differential-known-difference" {
        details.bind(d => refusal_digest(fixture, d)).unwrap_or("")
      } else {
        ""
      },
    })
  }
  report
}

///|
fn CoverageReport::complete(
  self : CoverageReport,
  allow_deferred~ : Bool,
) -> Bool {
  self.rows.all(row => {
    match row.execution_state {
      "executed" | "excluded" => true
      "deferred-platform" => allow_deferred
      _ => false
    }
  }) &&
  self.unclassified == 0 &&
  self.differential_executed ==
  self.differential_exact + self.differential_known_difference
}
