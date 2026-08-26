///|
fn perf_cli_environment(size : Int) -> Map[String, String] {
  let environment : Map[String, String] = Map([])
  for index in 0..<size {
    environment["JUST_TEST_" + index.to_string()] = "value"
  }
  environment
}

///|
fn bench_cli_parse(it : @bench.T, size : Int) -> Unit {
  let environment = perf_cli_environment(size)
  it.bench(fn() {
    it.keep(try! parse_arguments(["--list", "recipe"], environment))
  })
}

///|
test "bench cli parse environment-10" (it : @bench.T) {
  bench_cli_parse(it, 10)
}

///|
test "bench cli parse environment-100" (it : @bench.T) {
  bench_cli_parse(it, 100)
}

///|
test "bench cli parse environment-1000" (it : @bench.T) {
  bench_cli_parse(it, 1000)
}

///|
test "bench cli parse environment-5000" (it : @bench.T) {
  bench_cli_parse(it, 5000)
}
