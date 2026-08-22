///|
/// Merge dotenv entries while preserving the stable environment order needed
/// by CommandSpec construction.
fn merge_dotenv_entries(
  environment : Array[(String, String)],
  dotenv : ArrayView[(String, String)],
  override_environment : Bool,
) -> Array[(String, String)] {
  // Index the existing prefix once. This keeps inherited dotenv composition
  // linear in the number of entries rather than rescanning the prefix.
  let positions : Map[String, Int] = Map([])
  for index, entry in environment {
    if !positions.contains(entry.0) {
      positions[entry.0] = index
    }
  }
  for entry in dotenv {
    match positions.get(entry.0) {
      Some(index) => if override_environment { environment[index] = entry }
      None => {
        positions[entry.0] = environment.length()
        environment.push(entry)
      }
    }
  }
  environment
}
