///|
fn perf_loader_source(size : Int) -> Bytes {
  let text = StringBuilder()
  for index in 0..<size {
    text.write_string("recipe")
    text.write_string(index.to_string())
    text.write_string(":\n")
  }
  @utf8.encode(text.to_string())
}

///|
fn bench_loader_graph(it : @bench.T, size : Int) -> Unit {
  let host = @host.FakeHost::new(
    try! @path.PathValue::new("/workspace", Unix),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let root = try! @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(root, perf_loader_source(size))
  it.bench(fn() {
    it.keep(try! load_graph(host, root, @source.SourceId::new(1900 + size)))
  })
}

///|
test "bench loader graph recipes-10" (it : @bench.T) {
  bench_loader_graph(it, 10)
}

///|
test "bench loader graph recipes-100" (it : @bench.T) {
  bench_loader_graph(it, 100)
}

///|
test "bench loader graph recipes-1000" (it : @bench.T) {
  bench_loader_graph(it, 1000)
}

///|
test "bench loader graph recipes-5000" (it : @bench.T) {
  bench_loader_graph(it, 5000)
}
