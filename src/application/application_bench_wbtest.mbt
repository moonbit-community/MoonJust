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

///|
fn perf_project_source(size : Int) -> Bytes {
  let text = StringBuilder()
  for index in 0..<size {
    text.write_string("recipe")
    text.write_string(index.to_string())
    text.write_string(":\n")
  }
  @utf8.encode(text.to_string())
}

///|
fn bench_project_compile(it : @bench.T, size : Int) -> Unit {
  let cwd = try! @path.PathValue::new("/workspace", Unix)
  let root = try! @path.PathValue::new("/workspace/justfile", Unix)
  let host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  host.put_file(root, perf_project_source(size))
  let graph = try! @loader.load_graph(
    host,
    root,
    @source.SourceId::new(2100 + size),
  )
  it.bench(fn() { it.keep(try! compile_loaded_graph(graph)) })
}

///|
test "bench project compile recipes-10" (it : @bench.T) {
  bench_project_compile(it, 10)
}

///|
test "bench project compile recipes-100" (it : @bench.T) {
  bench_project_compile(it, 100)
}

///|
test "bench project compile recipes-1000" (it : @bench.T) {
  bench_project_compile(it, 1000)
}

///|
test "bench project compile recipes-5000" (it : @bench.T) {
  bench_project_compile(it, 5000)
}
