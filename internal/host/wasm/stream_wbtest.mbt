///|
async test "stream reads one open handle across short reads and pathname replacement" {
  let root = @async_fs.tmpdir(prefix="moonjust-stream")
  defer @async_fs.remove(root, recursive=true)
  let name = root + "/input"
  let path = @path.PathValue::new(
    name,
    ExecutionFs::new().current_dir().flavor(),
  )
  let original = b"a\x00\xffbcde"
  @async_fs.write_binary(name, original)
  @async_fs.write_binary(root + "/new", b"changed!")
  let mut opens = 0
  let reads = []
  let chunks = []
  let sum = @cache.ContentHasher::new()
  let meta = stream_open_file(
    path,
    4,
    chunk => {
      sum.update(chunk)
      chunks.push(chunk)
    },
    () => {
      opens += 1
      @async_fs.open(name, mode=ReadOnly)
    },
    (file, buffer, limit) => {
      if reads.is_empty() {
        @async_fs.rename(root + "/new", name)
      }
      reads.push(limit)
      file.read_into(buffer, max_len=Int32::min(2, limit))
    },
  )
  assert_true(meta.is_file())
  assert_eq(opens, 1)
  assert_eq(reads, [4, 4, 3, 1])
  assert_eq(chunks, [b"a\x00", b"\xffb", b"cd", b"e"])
  let expected = @cache.ContentHasher::new()
  expected.update(original)
  assert_eq(sum.finalize(), expected.finalize())
}

///|
async test "empty stream emits one empty chunk without reading past its boundary" {
  let root = @async_fs.tmpdir(prefix="moonjust-stream")
  defer @async_fs.remove(root, recursive=true)
  let name = root + "/empty"
  let path = @path.PathValue::new(
    name,
    ExecutionFs::new().current_dir().flavor(),
  )
  @async_fs.write_binary(name, b"")
  let chunks = []
  let mut opens = 0
  let mut reads = 0
  ignore(
    stream_open_file(
      path,
      4,
      chunk => chunks.push(chunk),
      () => {
        opens += 1
        @async_fs.open(name, mode=ReadOnly)
      },
      (file, buffer, limit) => {
        reads += 1
        file.read_into(buffer, max_len=limit)
      },
    ),
  )
  assert_eq(opens, 1)
  assert_eq(reads, 0)
  assert_eq(chunks, [b""])
}
