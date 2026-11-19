///|
fn concatenate_step_stream(
  steps : ArrayView[StepResult],
  use_stdout : Bool,
) -> Bytes {
  let output : Array[Byte] = []
  for step in steps {
    append_bytes(
      output,
      if use_stdout {
        step.stdout[:]
      } else {
        step.stderr[:]
      },
    )
  }
  Bytes::from_array(output)
}

///|
async fn write_expected(case_dir : String, result : CaseResult) -> Unit {
  @fs.write_binary(
    join(case_dir, "expected.status"),
    @utf8.encode(result.status.to_string() + "\n"),
  )
  @fs.write_binary(join(case_dir, "expected.stdout"), result.stdout)
  @fs.write_binary(join(case_dir, "expected.stderr"), result.stderr)
  @fs.write_binary(join(case_dir, "expected.tree"), result.tree)
  match result.merged {
    Some(bytes) => @fs.write_binary(join(case_dir, "expected.merged"), bytes)
    None => ()
  }
  let steps_root = join(case_dir, "steps")
  if @fs.exists(steps_root) {
    let names = @fs.readdir(steps_root, include_hidden=false, sort=true)
    for index, name in names {
      guard result.steps.get(index) is Some(step) else { continue }
      let directory = join(steps_root, name)
      @fs.write_binary(
        join(directory, "expected.status"),
        @utf8.encode(step.status.to_string() + "\n"),
      )
      @fs.write_binary(join(directory, "expected.stdout"), step.stdout)
      @fs.write_binary(join(directory, "expected.stderr"), step.stderr)
    }
  }
}

///|
async fn expected_snapshot(case_dir : String) -> CaseResult? {
  let steps_root = join(case_dir, "steps")
  if @fs.exists(steps_root) {
    let steps : Array[StepResult] = []
    for name in @fs.readdir(steps_root, include_hidden=false, sort=true) {
      let directory = join(steps_root, name)
      guard @fs.kind(directory) == Directory else { continue }
      guard @fs.exists(join(directory, "expected.status")) else { return None }
      let status = @string.parse_int(
        read_text(join(directory, "expected.status")).trim(),
      ) catch {
        _ => return None
      }
      steps.push({
        status,
        stdout: @fs.read_binary(join(directory, "expected.stdout")),
        stderr: @fs.read_binary(join(directory, "expected.stderr")),
      })
    }
    guard !steps.is_empty() else { return None }
    return Some({
      status: steps[steps.length() - 1].status,
      stdout: concatenate_step_stream(steps, true),
      stderr: concatenate_step_stream(steps, false),
      merged: None,
      tree: @fs.read_binary(join(case_dir, "expected.tree")),
      live: true,
      steps,
    })
  }
  guard @fs.exists(join(case_dir, "expected.status")) else { return None }
  let status = @string.parse_int(
    read_text(join(case_dir, "expected.status")).trim(),
  ) catch {
    _ => return None
  }
  let merged = if @fs.exists(join(case_dir, "expected.merged")) {
    Some(@fs.read_binary(join(case_dir, "expected.merged")))
  } else {
    None
  }
  let stdout = @fs.read_binary(join(case_dir, "expected.stdout"))
  let stderr = @fs.read_binary(join(case_dir, "expected.stderr"))
  Some({
    status,
    stdout,
    stderr,
    merged,
    tree: @fs.read_binary(join(case_dir, "expected.tree")),
    live: true,
    steps: [{ status, stdout, stderr, }],
  })
}

///|
fn append_bytes(output : Array[Byte], input : BytesView) -> Unit {
  for byte in input {
    output.push(byte)
  }
}

///|
fn normalized_tree_path(path : String, bytes : BytesView) -> String {
  guard path.has_prefix(".justcache/") && path.has_suffix(".json") else {
    return path
  }
  let name = path
    .strip_prefix(".justcache/")
    .unwrap_or(path)
    .strip_suffix(".json")
    .unwrap_or("")
  if name.length() == 64 &&
    name.all(fn(character) {
      character.is_ascii_digit() || (character >= 'a' && character <= 'f')
    }) {
    let text = @utf8.decode(bytes) catch { _ => "" }
    let recipe = match text.find("\"recipe\":\"") {
      Some(start) => {
        let tail = text[start + 10:]
        match tail.find("\"") {
          Some(end) => tail[:end].to_owned()
          None => "unknown"
        }
      }
      None => "unknown"
    }
    ".justcache/<CACHE_KEY-" + recipe + ">.json"
  } else {
    path
  }
}

///|
async fn append_tree_snapshot(
  current : String,
  relative : String,
  output : Array[Byte],
  root : String,
  links : Map[String, String],
) -> Unit {
  if relative == ".justcache" {
    let entries : Array[(String, Bytes)] = []
    for name in @fs.readdir(current, include_hidden=true, sort=true) {
      let full = join(current, name)
      if @fs.kind(full) == Regular {
        entries.push((name, @fs.read_binary(full)))
      }
    }
    entries.sort_by(fn(left, right) {
      normalized_tree_path(".justcache/" + left.0, left.1[:]).compare(
        normalized_tree_path(".justcache/" + right.0, right.1[:]),
      )
    })
    for _, entry in entries {
      let name = entry.0
      let raw_bytes = entry.1
      let bytes = normalize(raw_bytes, root)
      let path = normalized_tree_path(".justcache/" + name, raw_bytes[:])
      append_bytes(
        output,
        @utf8.encode(
          "file\t./" + path + "\t" + bytes.length().to_string() + "\n",
        )[:],
      )
      append_bytes(output, bytes[:])
      output.push(b'\n')
    }
    return
  }
  for name in @fs.readdir(current, include_hidden=true, sort=true) {
    let full = join(current, name)
    let raw_path = if relative.is_empty() {
      name
    } else {
      relative + "/" + name
    }
    match links.get(raw_path) {
      Some(target) => {
        append_bytes(
          output,
          @utf8.encode("link\t./" + raw_path + "\t" + target + "\n")[:],
        )
        continue
      }
      None => ()
    }
    match @fs.kind(full) {
      Directory => {
        append_bytes(output, @utf8.encode("dir\t./" + raw_path + "\n")[:])
        append_tree_snapshot(full, raw_path, output, root, links)
      }
      Regular => {
        let bytes = normalize(@fs.read_binary(full), root)
        let path = normalized_tree_path(raw_path, bytes[:])
        append_bytes(
          output,
          @utf8.encode(
            "file\t./" + path + "\t" + bytes.length().to_string() + "\n",
          )[:],
        )
        append_bytes(output, bytes[:])
        output.push(b'\n')
      }
      _ => append_bytes(output, @utf8.encode("other\t./" + raw_path + "\n")[:])
    }
  }
}

///|
async fn tree_snapshot(root : String) -> Bytes {
  let output : Array[Byte] = []
  let links : Map[String, String] = Map([])
  let metadata = link_metadata_path(root)
  if @fs.exists(metadata) {
    for line in @fs.read_text(metadata).split("\n") {
      let fields = line.split("\t").collect()
      if fields.length() == 2 && !fields[0].is_empty() {
        links[fields[0].to_owned()] = fields[1].to_owned()
      }
    }
  }
  append_tree_snapshot(root, "", output, root, links)
  Bytes::from_array(output)
}
