///|
test "evaluate one expression containing 48 builtin calls" {
  let term = "trim(uppercase(lowercase(' X ')))"
  let source = @source.Source::from_text(
    @source.SourceId::new(0),
    "builtin-cost",
    Array::make(16, term).join(" + "),
  )
  let expression = try! @parser.parse_expression(source)
  assert_eq(
    (try! @evaluator.evaluate(expression)).to_string(),
    "XXXXXXXXXXXXXXXX",
  )
}

///|
async test "stream one MiB and one byte through the production Wasm adapter" {
  let root = @fs.tmpdir(prefix="moonjust-stream-cost")
  defer @fs.remove(root, recursive=true)
  let file = root + "/input"
  let input = Bytes::from_array(
    Array::makei(1_048_577, i => (i % 251).to_byte()),
  )
  @fs.write_binary(file, input)
  let expected = @cache.ContentHasher::new()
  expected.update(input)
  let actual = @cache.ContentHasher::new()
  let host = @wasm_host.ExecutionFs::new()
  let path = @path.PathValue::new(file, host.current_dir().flavor())
  let mut chunks = 0
  @host_fs.stream_file(host, path, bytes => {
    chunks += 1
    actual.update(bytes)
  })
  assert_eq(chunks, 17)
  assert_eq(actual.finalize(), expected.finalize())
}
