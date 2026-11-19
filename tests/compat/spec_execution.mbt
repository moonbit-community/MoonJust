///|
fn upstream_test_names(text : String) -> Set[String] {
  let names : Set[String] = Set([])
  for raw in text.split("\n") {
    let name = raw.trim().to_owned()
    if !name.is_empty() {
      names.add(name)
    }
  }
  names
}

///|
fn outline_contains_spec(outline : String, spec : SpecCase) -> Bool {
  guard spec.local_test is Some(name) else { return false }
  guard location_parts(spec.fixture) is Some((path, line_number)) else {
    return false
  }
  let segments = path.split("/").collect()
  guard segments.last() is Some(file) else { return false }
  let package_path = segments[:segments.length() - 1].join("/")
  let location = "/" +
    package_path +
    " " +
    file.to_owned() +
    ":" +
    line_number.to_string() +
    " "
  let declaration = " name=\"" + name + "\""
  for line in outline.split("\n") {
    if line.contains(location) && line.has_suffix(declaration) {
      return true
    }
  }
  false
}

///|
async fn execute_moonbit_specs(
  specs : Map[String, SpecCase],
  failures : Array[String],
) -> Set[String] {
  let executed : Set[String] = Set([])
  let test_result = @testkit.run("moon", [
    "test", "--target", "wasm", "--no-parallelize",
  ])
  if test_result.status != 0 {
    failures.push("MoonBit spec test execution failed")
    return executed
  }
  let outline = @testkit.run("moon", ["test", "--target", "wasm", "--outline"])
  if outline.status != 0 {
    failures.push("MoonBit spec test outline failed")
    return executed
  }
  let outline_text = @utf8.decode(outline.stdout) catch {
    _ => {
      failures.push("MoonBit spec test outline is not UTF-8")
      return executed
    }
  }
  for upstream_test, spec in specs {
    let fixture_path = spec.fixture
      .split(":")
      .collect()
      .get(0)
      .unwrap_or("")
      .to_owned()
    if !fixture_path.has_suffix("upstream-fixtures.txt") &&
      outline_contains_spec(outline_text, spec) {
      executed.add(upstream_test)
    }
  }
  executed
}
