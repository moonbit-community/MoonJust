///|
fn perf_environment_entries(size : Int) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  for index in 0..<size {
    result.push(("KEY" + index.to_string(), "value"))
  }
  result
}

///|
fn bench_environment_merge(it : @bench.T, size : Int) -> Unit {
  let baseline = perf_environment_entries(size)
  let updates : Array[(String, String)] = []
  for index in 0..<size {
    updates.push(("KEY" + index.to_string(), "updated"))
  }
  it.bench(fn() {
    it.keep(merge_dotenv_entries(baseline.copy(), updates, true))
  })
}

///|
test "bench environment merge 10" (it : @bench.T) {
  bench_environment_merge(it, 10)
}

///|
test "bench environment merge 100" (it : @bench.T) {
  bench_environment_merge(it, 100)
}

///|
test "bench environment merge 1000" (it : @bench.T) {
  bench_environment_merge(it, 1000)
}

///|
test "bench environment merge 5000" (it : @bench.T) {
  bench_environment_merge(it, 5000)
}
