///|
fn utf8_line_starts(source : String) -> Array[Int] {
  let bytes = @utf8.encode(source)
  let starts = [0]
  for index, byte in bytes {
    if byte == b'\n' && index + 1 < bytes.length() {
      starts.push(index + 1)
    }
  }
  starts
}

///|
fn two_digits(value : Int) -> String {
  if value < 10 {
    "0\{value}"
  } else {
    value.to_string()
  }
}

///|
fn format_datetime_contract(value : @time.ZonedDateTime) -> String {
  let offset_seconds = value.offset().seconds()
  let (sign, absolute_offset) = if offset_seconds < 0 {
    ("-", -offset_seconds)
  } else {
    ("+", offset_seconds)
  }
  let offset_hour = absolute_offset / 3600
  let offset_minute = absolute_offset % 3600 / 60
  "\{value.year()}-\{two_digits(value.month())}-\{two_digits(value.day())}T\{two_digits(value.hour())}:\{two_digits(value.minute())}:\{two_digits(value.second())}\{sign}\{two_digits(offset_hour)}\{two_digits(offset_minute)}"
}

///|
fn top_level_just_lines(markdown : String) -> Array[String] {
  let doc = @cmark.Doc::from_string(layout=true, locs=true, markdown)
  guard doc.block is Blocks(blocks) else { return [] }
  let lines = []
  for block in blocks.v {
    guard block is CodeBlock(node) else { continue }
    guard node.v.layout is Fenced(_) else { continue }
    guard node.v.info_string is Some(info_node) else { continue }
    let info = info_node.v
    if info == "just" || info.has_prefix("just ") || info.has_prefix("just\t") {
      for line in node.v.code {
        lines.push(line.v)
      }
    }
  }
  lines
}

///|
test "source spans use UTF-8 bytes" {
  let source = "a\n中\r\n🙂"
  let bytes = @utf8.encode(source)
  assert_eq(source.length(), 7)
  assert_eq(bytes.length(), 11)
  assert_eq(utf8_line_starts(source), [0, 2, 7])
  assert_eq(@utf8.decode(bytes[2:5]), "中")
  assert_eq(@utf8.decode(bytes[7:11]), "🙂")
}

///|
test "invalid UTF-8 is a typed decoding failure" {
  let rejected = try {
    @utf8.decode(b"\xff") |> ignore
    false
  } catch {
    Malformed(_) => true
  }
  assert_true(rejected)
}

///|
test "regexp supports captures and Unicode classes" {
  let matcher = @regexp.compile("^(?<word>\\p{L}+)-([0-9]+)$")
  guard matcher.match_("Moon-42") is Some(result) else {
    fail("expected regular expression match")
  }
  assert_eq(result.get(0).map(StringView::to_owned), Some("Moon-42"))
  assert_eq(result.get(1).map(StringView::to_owned), Some("Moon"))
  assert_eq(result.get(2).map(StringView::to_owned), Some("42"))
  assert_eq(matcher.group_by_name("word"), Some(1))
  assert_true(@regexp.compile("^\\p{L}+$").match_("Μoon") is Some(_))
}

///|
test "regexp rejects unsupported Unicode script classes" {
  let rejected = try {
    @regexp.compile("^\\p{Greek}+$") |> ignore
    false
  } catch {
    RegexpError(err=_, source_fragment=_) => true
  }
  assert_true(rejected)
}

///|
test "regexp rejects Rust-style named capture syntax" {
  let rejected = try {
    @regexp.compile("(?P<word>[a-z]+)") |> ignore
    false
  } catch {
    RegexpError(err=_, source_fragment=_) => true
  }
  assert_true(rejected)
}

///|
test "regexp rejects unsupported look-around" {
  let rejected = try {
    @regexp.compile("a(?=b)") |> ignore
    false
  } catch {
    RegexpError(err=_, source_fragment=_) => true
  }
  assert_true(rejected)
}

///|
test "regexp package accepts backreferences that MoonJust must reject" {
  let matcher = @regexp.compile("^(?<word>[a-z]+)-\\k<word>$")
  assert_true(matcher.match_("same-same") is Some(_))
  assert_true(matcher.match_("same-other") is None)
}

///|
test "cmark identifies source-aware just fences" {
  let markdown =
    #|中intro
    #|
    #|```just extra
    #|hello:
    #|  echo hello
    #|```
    #|
    #|```sh
    #|echo ignored
    #|```
    #|
  let doc = @cmark.Doc::from_string(layout=true, locs=true, markdown)
  guard doc.block is Blocks(blocks) else {
    fail("expected top-level CommonMark blocks")
  }
  let code_blocks = blocks.v
    .to_array()
    .filter_map(block => {
      match block {
        CodeBlock(node) => Some(node)
        _ => None
      }
    })
  assert_eq(code_blocks.length(), 2)
  let just = code_blocks[0]
  assert_eq(just.v.info_string.map(node => node.v), Some("just extra"))
  assert_eq(just.v.code.to_array().map(node => node.v), [
    "hello:", "  echo hello",
  ])
  assert_false(just.meta.loc.is_none())
  assert_false(just.v.code[0].meta.loc.is_none())
  assert_eq(utf8_line_starts(markdown)[3], 24)
  assert_eq(just.v.code[0].meta.loc.first_ccode, 22)
  assert_eq(code_blocks[1].v.info_string.map(node => node.v), Some("sh"))
}

///|
test "cmark can express upstream tangle block selection" {
  assert_eq(top_level_just_lines("```just\nselected:\n```\n"), ["selected:"])
  assert_eq(top_level_just_lines("```just extra\nselected:\n```\n"), [
    "selected:",
  ])
  assert_eq(top_level_just_lines("``` just\nselected:\n```\n"), ["selected:"])
  assert_eq(top_level_just_lines("~~~just\nselected:\n~~~\n"), ["selected:"])
  assert_eq(top_level_just_lines("```just\nselected:\n"), ["selected:"])
  assert_eq(top_level_just_lines("```justfile\nignored:\n```\n"), [])
  assert_eq(top_level_just_lines("```JUST\nignored:\n```\n"), [])
  assert_eq(top_level_just_lines("    ```just\nignored:\n```\n"), [])
  assert_eq(top_level_just_lines("> ```just\n> ignored:\n> ```\n"), [])
  assert_eq(top_level_just_lines("- item\n\n  ```just\n  ignored:\n  ```\n"), [])
  assert_eq(top_level_just_lines("<!--\n```just\nignored:\n```\n-->\n"), [])
  assert_eq(top_level_just_lines("````\n```just\nignored:\n```\n````\n"), [])
}

///|
test "time model handles UTC and fixed offsets" {
  let epoch = @time.ZonedDateTime::from_unix_second(0, zone=@time.utc_zone)
  assert_eq(epoch.year(), 1970)
  assert_eq(epoch.month(), 1)
  assert_eq(epoch.day(), 1)
  assert_eq(epoch.hour(), 0)
  assert_eq(epoch.offset().seconds(), 0)

  let plus_eight = @time.fixed_zone("Asia/Shanghai-fixed", 8 * 60 * 60)
  let local_time = @time.ZonedDateTime::from_unix_second(0, zone=plus_eight)
  assert_eq(local_time.hour(), 8)
  assert_eq(local_time.offset().seconds(), 8 * 60 * 60)
  assert_eq(format_datetime_contract(epoch), "1970-01-01T00:00:00+0000")
  assert_eq(format_datetime_contract(local_time), "1970-01-01T08:00:00+0800")
}
