///|
fn perf_source(size : Int) -> (@source.Source, Array[Int]) {
  let text = StringBuilder()
  for index in 0..<size {
    text.write_string("recipe")
    text.write_string(index.to_string())
    text.write_string(" 中🙂\n")
  }
  let source = @source.Source::from_text(
    @source.SourceId::new(1701),
    "benchmark.just",
    text.to_string(),
  )
  let offsets : Array[Int] = []
  let length = source.length()
  let bytes = source.bytes()
  for offset in 0..<length {
    if !(bytes[offset] >= 0x80 && bytes[offset] <= 0xBF) {
      offsets.push(offset)
    }
  }
  offsets.push(length)
  (source, offsets)
}

///|
fn bench_source_locate(it : @bench.T, size : Int) -> Unit {
  let (source, offsets) = perf_source(size)
  it.bench(fn() {
    let mut checksum = 0
    for offset in offsets {
      checksum += try! source.locate(offset).scalar_column()
    }
    it.keep(checksum)
  })
}

///|
test "bench source locate 10" (it : @bench.T) {
  bench_source_locate(it, 10)
}

///|
test "bench source locate 100" (it : @bench.T) {
  bench_source_locate(it, 100)
}

///|
test "bench source locate 1000" (it : @bench.T) {
  bench_source_locate(it, 1000)
}

///|
test "bench source locate 5000" (it : @bench.T) {
  bench_source_locate(it, 5000)
}
