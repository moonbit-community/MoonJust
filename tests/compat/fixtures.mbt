///|
async fn fixture_structure_errors(
  name : String,
  case_dir : String,
) -> Array[String] {
  let errors : Array[String] = []
  for
    required in [
      "compat-id", "expectation", "expected.status", "expected.stdout", "expected.stderr",
      "expected.tree",
    ] {
    if !@fs.exists(join(case_dir, required)) {
      errors.push(name + ": fixture is missing required file " + required)
    }
  }
  if !@fs.exists(join(case_dir, "argv.txt")) &&
    !@fs.exists(join(case_dir, "steps")) {
    errors.push(name + ": fixture has no explicit argv or step input")
  }
  if @fs.exists(join(case_dir, "stdout.regex")) ||
    @fs.exists(join(case_dir, "stderr.regex")) {
    errors.push(name + ": regex expectations are forbidden")
  }
  errors
}

///|
fn join(left : String, right : String) -> String {
  @path.Path(left).join(Path(right)).to_string()
}

///|
fn symlink_target(
  root : String,
  link : String,
  target : String,
  platform : String,
) -> String {
  guard platform == "windows" && !@path.Path(target).is_absolute() else {
    return target
  }
  let parent = match link.rev_find("/") {
    Some(index) => link[:index].to_owned()
    None => ""
  }
  join(join(root, parent), target)
}

///|
/// Keep runner-only symlink metadata outside the isolated project tree.
fn link_metadata_path(root : String) -> String {
  root + ".moonjust-tree-links"
}

///|
fn expand(value : String, root : String) -> String {
  value
  .replace_all(old="<CASE_ROOT>", new=root)
  .replace_all(old="<TAB>", new="\t")
  .replace_all(old="<TWO_SPACES>", new="  ")
}

///|
fn strip_cr(line : StringView) -> StringView {
  line.strip_suffix("\r").unwrap_or(line)
}

///|
async fn read_text(path : String) -> String {
  @fs.read_text(path) catch {
    _ => ""
  }
}

///|
async fn read_optional_bytes(path : String) -> Bytes {
  if @fs.exists(path) {
    @fs.read_binary(path)
  } else {
    b""
  }
}

///|
async fn arguments(case_dir : String, root : String) -> Array[String] {
  let path = join(case_dir, "argv.txt")
  if !@fs.exists(path) {
    return []
  }
  let result : Array[String] = []
  for raw in read_text(path).split("\n") {
    let line = strip_cr(raw)
    if line == "<EMPTY>" {
      result.push("")
    } else if !line.is_empty() {
      result.push(expand(line.to_owned(), root))
    }
  }
  result
}

///|
fn isolated_environment(root : String) -> Map[String, String] {
  let values : Map[String, String] = Map([])
  values["PATH"] = @env.get_env_var("PATH").unwrap_or("/usr/bin:/bin")
  values["HOME"] = join(root, "home")
  values["LC_ALL"] = "C"
  values["LANG"] = "C"
  values["TZ"] = "UTC"
  values["JUST_COLOR"] = "never"
  values
}

///|
async fn environment(case_dir : String, root : String) -> Map[String, String] {
  let values = isolated_environment(root)
  let path = join(case_dir, "env.list")
  if !@fs.exists(path) {
    return values
  }
  for raw in read_text(path).split("\n") {
    let line = strip_cr(raw)
    guard !line.is_empty() && line.find("=") is Some(index) else { continue }
    let name = line[:index].to_owned()
    let value = line[index + 1:].to_owned()
    values[name] = expand(value, root)
  }
  values
}

///|
async fn copy_tree(source : String, destination : String) -> Unit {
  if !@fs.exists(source) {
    return
  }
  if !@fs.exists(destination) {
    @fs.mkdir(destination, recursive=true)
  }
  for name in @fs.readdir(source, include_hidden=true, sort=true) {
    let from = join(source, name)
    let to = join(destination, name)
    match @fs.kind(from) {
      Directory => copy_tree(from, to)
      Regular => @fs.write_binary(to, @fs.read_binary(from))
      _ => ()
    }
  }
}

///|
async fn apply_symlinks(
  directory : String,
  root : String,
  platform : String,
) -> Unit {
  let descriptor = join(directory, "symlinks.list")
  if !@fs.exists(descriptor) {
    return
  }
  let link_metadata = link_metadata_path(root)
  for raw in read_text(descriptor).split("\n") {
    let fields = raw.split("\t").collect()
    if fields.length() < 2 {
      continue
    }
    let raw_target = fields[1].to_owned()
    let target = symlink_target(
      root,
      fields[0].to_owned(),
      raw_target,
      platform,
    )
    @fs.symlink(
      join(root, fields[0].to_owned())[:],
      target=target[:],
      force_symlink=true,
    )
    // A fixture may mark a host executable symlink as a tree link. Recording
    // the target keeps snapshots portable without copying ELF/Mach-O bytes.
    if fields.length() >= 3 && fields[2] == "link" {
      let existing = if @fs.exists(link_metadata) {
        @fs.read_text(link_metadata)
      } else {
        ""
      }
      @fs.write_binary(
        link_metadata,
        @utf8.encode(
          existing + fields[0].to_owned() + "\t" + fields[1].to_owned() + "\n",
        ),
      )
    }
  }
}

///|
async fn apply_expanded_files(directory : String, root : String) -> Unit {
  let descriptor = join(directory, "expand.list")
  if !@fs.exists(descriptor) {
    return
  }
  for raw in read_text(descriptor).split("\n") {
    let relative = raw.trim().to_owned()
    if relative.is_empty() {
      continue
    }
    let path = join(root, relative)
    let text = @fs.read_text(path)
    @fs.write_binary(path, @utf8.encode(expand(text, root)))
  }
}

///|
async fn apply_directories(directory : String, root : String) -> Unit {
  let descriptor = join(directory, "directories.list")
  if !@fs.exists(descriptor) {
    return
  }
  for raw in read_text(descriptor).split("\n") {
    let relative = raw.trim().to_owned()
    if !relative.is_empty() {
      let path = join(root, relative)
      if !@fs.exists(path) {
        @fs.mkdir(path, recursive=true)
      }
    }
  }
}

///|
async fn apply_trimmed_files(directory : String, root : String) -> Unit {
  let descriptor = join(directory, "trim-final-newline.list")
  if !@fs.exists(descriptor) {
    return
  }
  for raw in read_text(descriptor).split("\n") {
    let relative = raw.trim().to_owned()
    if relative.is_empty() {
      continue
    }
    let path = join(root, relative)
    let bytes = @fs.read_binary(path)
    if bytes.length() > 0 && bytes[bytes.length() - 1] == b'\n' {
      @fs.write_binary(path, bytes[:bytes.length() - 1].to_owned())
    }
  }
}

///|
async fn prepare_root(
  case_dir : String,
  root : String,
  cwd : String,
  platform : String,
) -> Unit {
  if !@fs.exists(join(root, "home")) {
    @fs.mkdir(join(root, "home"), recursive=true)
  }
  copy_tree(join(case_dir, "tree"), root)
  apply_directories(case_dir, root)
  apply_trimmed_files(case_dir, root)
  if !cwd.is_empty() && !@fs.exists(join(root, cwd)) {
    @fs.mkdir(join(root, cwd), recursive=true)
  }
  apply_expanded_files(case_dir, root)
  apply_symlinks(case_dir, root, platform)
}

///|
async fn apply_step_changes(
  step_dir : String,
  root : String,
  platform : String,
) -> Unit {
  copy_tree(join(step_dir, "write"), root)
  apply_directories(step_dir, root)
  apply_trimmed_files(step_dir, root)
  apply_expanded_files(step_dir, root)
  apply_symlinks(step_dir, root, platform)
  let remove = join(step_dir, "remove.list")
  if @fs.exists(remove) {
    for raw in read_text(remove).split("\n") {
      let relative = raw.trim().to_owned()
      if relative.is_empty() {
        continue
      }
      let path = join(root, relative)
      @fs.remove(path, recursive=true) catch {
        _ => @fs.remove(path[:]) catch { _ => () }
      }
    }
  }
}
