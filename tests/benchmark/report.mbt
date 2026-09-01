///|
fn json_string(value : String) -> String {
  "\"" +
  value.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"") +
  "\""
}

///|
async fn toolchain_versions() -> (String, String, String) {
  let result = @testkit.run("moon", ["version", "--all"])
  let text = @utf8.decode(result.stdout) catch { _ => "" }
  let mut moon = "unknown"
  let mut moonc = "unknown"
  let mut moonrun = "unknown"
  for line in text.split("\n") {
    let value = line.trim().to_owned()
    if value.has_prefix("moon ") {
      moon = value
    } else if value.has_prefix("moonc ") {
      moonc = value
    } else if value.has_prefix("moonrun ") {
      moonrun = value
    }
  }
  (moon, moonc, moonrun)
}

///|
fn workload_report_json(
  workload : Workload,
  fixture : Fixture,
  measurements : Measurements,
  settings : BenchmarkSettings,
) -> String {
  let candidate_median = median(measurements.candidate.copy())
  let official_median = median(measurements.official.copy())
  let candidate_p95 = p95(measurements.candidate.copy())
  let official_p95 = p95(measurements.official.copy())
  let (ci_low, ci_high) = ratio_ci(
    measurements.candidate,
    measurements.official,
  )
  "{" +
  "\"target\":" +
  json_string(settings.target) +
  ",\"workload\":" +
  json_string(workload.name) +
  ",\"workload_size\":" +
  workload.size.to_string() +
  ",\"calibration_ms\":" +
  workload.calibration_ms.to_string() +
  ",\"profile\":" +
  json_string(settings.profile) +
  ",\"warmups\":" +
  settings.warmups.to_string() +
  ",\"batches\":" +
  settings.batches.to_string() +
  ",\"samples_per_batch\":" +
  settings.rounds.to_string() +
  ",\"candidate_samples\":" +
  measurements.candidate.length().to_string() +
  ",\"official_samples\":" +
  measurements.official.length().to_string() +
  ",\"candidate_samples_ms\":" +
  int64_json(measurements.candidate) +
  ",\"official_samples_ms\":" +
  int64_json(measurements.official) +
  ",\"batch_ratios\":" +
  double_json(measurements.batch_ratios) +
  ",\"candidate_median_ms\":" +
  candidate_median.to_string() +
  ",\"official_median_ms\":" +
  official_median.to_string() +
  ",\"candidate_p95_ms\":" +
  candidate_p95.to_string() +
  ",\"official_p95_ms\":" +
  official_p95.to_string() +
  ",\"median_ratio\":" +
  ratio(candidate_median, official_median).to_string() +
  ",\"batch_ratio_median\":" +
  median_double(measurements.batch_ratios.copy()).to_string() +
  ",\"p95_ratio\":" +
  ratio(candidate_p95, official_p95).to_string() +
  ",\"ci95_low\":" +
  ci_low.to_string() +
  ",\"ci95_high\":" +
  ci_high.to_string() +
  ",\"fixture_setup_ms\":" +
  fixture.setup_ms.to_string() +
  ",\"behavior_check_ms\":" +
  measurements.behavior_ms.to_string() +
  ",\"sample_complete\":true,\"failure_reason\":null}"
}

///|
fn exceeds_gate(
  target : String,
  name : String,
  median_ratio : Double,
  p95_ratio : Double,
) -> Bool {
  let median_limit = if target == "wasm" { 3.0 } else { 1.10 }
  let p95_limit = if target == "wasm" {
    if name == "startup-version" {
      2.0
    } else {
      3.0
    }
  } else {
    1.25
  }
  median_ratio > median_limit || p95_ratio > p95_limit
}

///|
fn report_json(
  settings : BenchmarkSettings,
  reports : ArrayView[String],
  runner_prepare_ms : Int64,
  moon_version : String,
  moonc_version : String,
  moonrun_version : String,
) -> String {
  let commit = @env.get_env_var("GITHUB_SHA").unwrap_or("unknown")
  let runner_os = @env.get_env_var("RUNNER_OS").unwrap_or("local")
  let runner_arch = @env.get_env_var("RUNNER_ARCH").unwrap_or("unknown")
  "{\"schema_version\":2,\"commit\":" +
  json_string(commit) +
  ",\"official_just_version\":\"1.57.0\"" +
  ",\"moon_version\":" +
  json_string(moon_version) +
  ",\"moonc_version\":" +
  json_string(moonc_version) +
  ",\"moonrun_version\":" +
  json_string(moonrun_version) +
  ",\"runner_os\":" +
  json_string(runner_os) +
  ",\"runner_arch\":" +
  json_string(runner_arch) +
  ",\"target\":" +
  json_string(settings.target) +
  ",\"profile\":" +
  json_string(settings.profile) +
  ",\"runner_prepare_ms\":" +
  runner_prepare_ms.to_string() +
  ",\"thresholds\":{\"native_median\":1.1,\"native_p95\":1.25,\"wasm_median\":3.0,\"wasm_startup\":2.0}" +
  ",\"workloads\":[" +
  reports.join(",") +
  "]}\n"
}
