///|
test "bench UTF-8 source encoding" (bench : @bench.T) {
  let source =
    #|build target: dependency
    #|  echo "MoonJust 中文 🙂"
    #|  echo "second recipe line"
    #|  echo "third recipe line"
    #|
  bench.bench(() => bench.keep(@utf8.encode(source)))
}

///|
test "bench cached regexp match" (bench : @bench.T) {
  let matcher = @regexp.compile("^(?<word>\\p{L}+)-([0-9]+)$")
  bench.bench(() => bench.keep(matcher.match_("MoonJust-157")))
}

///|
test "bench regexp compile and match" (bench : @bench.T) {
  bench.bench(() => {
    let matcher = @regexp.compile("^(?<word>\\p{L}+)-([0-9]+)$") catch {
      _ => abort("static benchmark expression must compile")
    }
    bench.keep(matcher.match_("MoonJust-157"))
  })
}

///|
test "bench CommonMark parse with layout and locations" (bench : @bench.T) {
  let markdown =
    #|# Build tasks
    #|
    #|```just
    #|build target: dependency
    #|  echo "MoonJust 中文 🙂"
    #|```
    #|
  bench.bench(() => {
    bench.keep(@cmark.Doc::from_string(layout=true, locs=true, markdown))
  })
}
